// Copyright (C) 2021 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package aidl

import (
	"android/soong/aidl_library"
	"android/soong/android"
	"reflect"

	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/google/blueprint"
	"github.com/google/blueprint/proptools"
)

var (
	aidlDumpApiRule = pctx.StaticRule("aidlDumpApiRule", blueprint.RuleParams{
		Command: `rm -rf "${outDir}" && mkdir -p "${outDir}" && ` +
			`${aidlCmd} --dumpapi ${imports} ${optionalFlags} --out ${outDir} ${in} && ` +
			`${aidlHashGen} ${outDir} ${latestVersion} ${hashFile}`,
		CommandDeps: []string{"${aidlCmd}", "${aidlHashGen}"},
	}, "optionalFlags", "imports", "outDir", "hashFile", "latestVersion")

	aidlCheckApiRule = pctx.StaticRule("aidlCheckApiRule", blueprint.RuleParams{
		Command: `(${aidlCmd} ${optionalFlags} --checkapi=${checkApiLevel} ${imports} ${old} ${new} && touch ${out}) || ` +
			`(cat ${messageFile} && exit 1)`,
		CommandDeps: []string{"${aidlCmd}"},
		Description: "AIDL CHECK API: ${new} against ${old}",
	}, "optionalFlags", "imports", "old", "new", "messageFile", "checkApiLevel")

	aidlVerifyHashRule = pctx.StaticRule("aidlVerifyHashRule", blueprint.RuleParams{
		Command: `if [ $$(cd '${apiDir}' && { find ./ -name "*.aidl" -print0 | LC_ALL=C sort -z | xargs -0 sha1sum && echo ${version}; } | sha1sum | cut -d " " -f 1) = $$(tail -1 '${hashFile}') ]; then ` +
			`touch ${out}; else cat '${messageFile}' && exit 1; fi`,
		Description: "Verify ${apiDir} files have not been modified",
	}, "apiDir", "version", "messageFile", "hashFile")
)

// Like android.OtherModuleProvider(), but will throw an error if the provider was not set
func expectOtherModuleProvider[K any](ctx android.ModuleContext, module blueprint.Module, provider blueprint.ProviderKey[K]) K {
	result, ok := android.OtherModuleProvider(ctx, module, provider)
	if !ok {
		var zero K
		ctx.ModuleErrorf("Expected module %q to have provider %v, but it did not.", module.Name(), zero)
		return zero
	}
	return result
}

type aidlApiInfo struct {
	// If unstable is true, there will be no exported api for this aidl interface.
	// All other fields of this provider will be nil, and none of the api build rules will be
	// generated.
	Unstable bool

	// for triggering api check for version X against version X-1
	CheckApiTimestamps android.Paths

	// for triggering check that files have not been modified
	CheckHashTimestamps android.Paths

	// for triggering freezing API as the new version
	FreezeApiTimestamp android.Path

	// for checking for active development on unfrozen version
	HasDevelopment android.Path
}

var aidlApiProvider = blueprint.NewProvider[aidlApiInfo]()

func (m *aidlInterface) apiDir() string {
	return filepath.Join(aidlApiDir, m.ModuleBase.Name())
}

type apiDump struct {
	version  string
	dir      android.Path
	files    android.Paths
	hashFile android.OptionalPath
}

func (m *aidlInterface) createApiDumpFromSource(ctx android.ModuleContext) apiDump {
	rawSrcs, aidlRoot := m.srcsForVersion(ctx, m.nextVersion())
	srcs, imports := getPaths(ctx, rawSrcs, aidlRoot)

	if ctx.Failed() {
		return apiDump{}
	}

	// dumpapi uses imports for ToT("") version
	deps := getDeps(ctx, m.getImports(m.nextVersion()))
	imports = append(imports, deps.imports...)

	var apiDir android.WritablePath
	var apiFiles android.WritablePaths
	var hashFile android.WritablePath

	apiDir = android.PathForModuleOut(ctx, "dump")
	for _, src := range srcs {
		outFile := android.PathForModuleOut(ctx, "dump", src.Rel())
		apiFiles = append(apiFiles, outFile)
	}
	hashFile = android.PathForModuleOut(ctx, "dump", ".hash")

	var optionalFlags []string
	if !proptools.Bool(m.properties.Unstable) {
		optionalFlags = append(optionalFlags, "--structured")
	}
	if m.properties.Stability != nil {
		optionalFlags = append(optionalFlags, "--stability", *m.properties.Stability)
	}
	if proptools.Bool(m.properties.Dumpapi.No_license) {
		optionalFlags = append(optionalFlags, "--no_license")
	}
	optionalFlags = append(optionalFlags, wrap("-p", deps.preprocessed.Strings(), "")...)

	version := nextVersion(m.getVersions())
	ctx.Build(pctx, android.BuildParams{
		Rule:      aidlDumpApiRule,
		Outputs:   append(apiFiles, hashFile),
		Inputs:    srcs,
		Implicits: deps.preprocessed,
		Args: map[string]string{
			"optionalFlags": strings.Join(optionalFlags, " "),
			"imports":       strings.Join(wrap("-I", imports, ""), " "),
			"outDir":        apiDir.String(),
			"hashFile":      hashFile.String(),
			"latestVersion": versionForHashGen(version),
		},
	})
	return apiDump{version, apiDir, apiFiles.Paths(), android.OptionalPathForPath(hashFile)}
}

func wrapWithDiffCheckIfElse(conditionFile android.Path, rb *android.RuleBuilder, writer func(*android.RuleBuilderCommand), elseBlock func(*android.RuleBuilderCommand)) {
	rbc := rb.Command()
	rbc.Text("if [ \"$(cat ").Input(conditionFile).Text(")\" = \"1\" ]; then")
	writer(rbc)
	rbc.Text("; else")
	elseBlock(rbc)
	rbc.Text("; fi")
}

func wrapWithDiffCheckIf(conditionFile android.Path, rb *android.RuleBuilder, writer func(*android.RuleBuilderCommand), needToWrap bool) {
	rbc := rb.Command()
	if needToWrap {
		rbc.Text("if [ \"$(cat ").Input(conditionFile).Text(")\" = \"1\" ]; then")
	}
	writer(rbc)
	if needToWrap {
		rbc.Text("; fi")
	}
}

// Migrate `versions` into `version_with_info`, and then append a version if it isn't nil
func (m *aidlInterface) migrateAndAppendVersion(
	ctx android.ModuleContext,
	hasDevelopment android.Path,
	rb *android.RuleBuilder,
	version *string,
	transitive bool,
) {
	isFreezingApi := version != nil

	// Remove `versions` property which is deprecated.
	wrapWithDiffCheckIf(hasDevelopment, rb, func(rbc *android.RuleBuilderCommand) {
		rbc.BuiltTool("bpmodify").
			Text("-w -m " + m.ModuleBase.Name()).
			Text("-parameter versions -remove-property").
			Text(android.PathForModuleSrc(ctx, "Android.bp").String())
	}, isFreezingApi)

	var versions []string
	if len(m.properties.Versions_with_info) == 0 {
		versions = append(versions, m.getVersions()...)
	}
	if isFreezingApi {
		versions = append(versions, *version)
	}
	for _, v := range versions {
		importIfaces := make(map[string]*aidlInterface)
		ctx.VisitDirectDeps(func(dep android.Module) {
			if _, ok := ctx.OtherModuleDependencyTag(dep).(importInterfaceDepTag); ok {
				other := dep.(*aidlInterface)
				importIfaces[other.BaseModuleName()] = other
			}
		})
		imports := make([]string, 0, len(m.getImportsForVersion(v)))
		needTransitiveFreeze := isFreezingApi && v == *version && transitive

		if needTransitiveFreeze {
			importApis := make(map[string]aidlApiInfo)
			for name, intf := range importIfaces {
				importApis[name] = expectOtherModuleProvider(ctx, intf, aidlApiProvider)
			}
			wrapWithDiffCheckIf(hasDevelopment, rb, func(rbc *android.RuleBuilderCommand) {
				rbc.BuiltTool("bpmodify").
					Text("-w -m " + m.ModuleBase.Name()).
					Text("-parameter versions_with_info -add-literal '").
					Text(fmt.Sprintf(`{version: "%s", imports: [`, v))

				for _, im := range m.getImportsForVersion(v) {
					moduleName, version := parseModuleWithVersion(im)

					// Invoke an imported interface's freeze-api only if it depends on ToT version explicitly or implicitly.
					if version == importIfaces[moduleName].nextVersion() || !hasVersionSuffix(im) {
						rb.Command().Text(fmt.Sprintf(`echo "Call %s-freeze-api because %s depends on %s."`, moduleName, m.ModuleBase.Name(), moduleName))
						rbc.Implicit(importApis[moduleName].FreezeApiTimestamp)
					}
					if hasVersionSuffix(im) {
						rbc.Text(fmt.Sprintf(`"%s",`, im))
					} else {
						rbc.Text("\"" + im + "-V'" + `$(if [ "$(cat `).
							Input(importApis[im].HasDevelopment).
							Text(`)" = "1" ]; then echo "` + importIfaces[im].nextVersion() +
								`"; else echo "` + importIfaces[im].latestVersion() + `"; fi)'", `)
					}
				}
				rbc.Text("]}' ").
					Text(android.PathForModuleSrc(ctx, "Android.bp").String()).
					Text("&&").
					BuiltTool("bpmodify").
					Text("-w -m " + m.ModuleBase.Name()).
					Text("-parameter frozen -set-bool true").
					Text(android.PathForModuleSrc(ctx, "Android.bp").String())
			}, isFreezingApi)
		} else {
			for _, im := range m.getImportsForVersion(v) {
				if hasVersionSuffix(im) {
					imports = append(imports, im)
				} else {
					versionSuffix := importIfaces[im].latestVersion()
					if !importIfaces[im].hasVersion() ||
						importIfaces[im].isExplicitlyUnFrozen() {
						versionSuffix = importIfaces[im].nextVersion()
					}
					imports = append(imports, im+"-V"+versionSuffix)
				}
			}
			importsStr := strings.Join(wrap(`"`, imports, `"`), ", ")
			data := fmt.Sprintf(`{version: "%s", imports: [%s]}`, v, importsStr)

			// Also modify Android.bp file to add the new version to the 'versions_with_info' property.
			wrapWithDiffCheckIf(hasDevelopment, rb, func(rbc *android.RuleBuilderCommand) {
				rbc.BuiltTool("bpmodify").
					Text("-w -m " + m.ModuleBase.Name()).
					Text("-parameter versions_with_info -add-literal '" + data + "' ").
					Text(android.PathForModuleSrc(ctx, "Android.bp").String()).
					Text("&&").
					BuiltTool("bpmodify").
					Text("-w -m " + m.ModuleBase.Name()).
					Text("-parameter frozen -set-bool true").
					Text(android.PathForModuleSrc(ctx, "Android.bp").String())
			}, isFreezingApi)
		}
	}
}

func (m *aidlInterface) makeApiDumpAsVersion(
	ctx android.ModuleContext,
	hasDevelopment android.Path,
	dump apiDump,
	version string,
) android.WritablePath {
	creatingNewVersion := version != currentVersion
	moduleDir := android.PathForModuleSrc(ctx).String()
	targetDir := filepath.Join(moduleDir, m.apiDir(), version)
	rb := android.NewRuleBuilder(pctx, ctx)
	transitive := ctx.Config().IsEnvTrue("AIDL_TRANSITIVE_FREEZE")
	var actionWord string
	if creatingNewVersion {
		actionWord = "Making"
		// We are asked to create a new version. But before doing that, check if the given
		// dump is the same as the latest version. If so, don't create a new version,
		// otherwise we will be unnecessarily creating many versions.
		// Copy the given dump to the target directory only when the equality check failed
		// (i.e. `has_development` file contains "1").
		wrapWithDiffCheckIf(hasDevelopment, rb, func(rbc *android.RuleBuilderCommand) {
			rbc.Text("mkdir -p " + targetDir + " && ").
				Text("cp -rf " + dump.dir.String() + "/. " + targetDir).Implicits(dump.files)
		}, true /* needToWrap */)
		wrapWithDiffCheckIfElse(hasDevelopment, rb, func(rbc *android.RuleBuilderCommand) {
			rbc.Text(fmt.Sprintf(`echo "There is change between ToT version and the latest stable version. Freezing %s-V%s."`, m.ModuleBase.Name(), version))
		}, func(rbc *android.RuleBuilderCommand) {
			rbc.Text(fmt.Sprintf(`echo "There is no change from the latest stable version of %s. Nothing happened."`, m.ModuleBase.Name()))
		})
		m.migrateAndAppendVersion(ctx, hasDevelopment, rb, &version, transitive)
	} else {
		actionWord = "Updating"
		if !m.isExplicitlyUnFrozen() {
			rb.Command().BuiltTool("bpmodify").
				Text("-w -m " + m.ModuleBase.Name()).
				Text("-parameter frozen -set-bool false").
				Text(android.PathForModuleSrc(ctx, "Android.bp").String())

		}
		// We are updating the current version. Don't copy .hash to the current dump
		rb.Command().Text("mkdir -p " + targetDir)
		rb.Command().Text("rsync --recursive --update --delete-before " + dump.dir.String() + "/* " + targetDir).Implicits(dump.files)
		m.migrateAndAppendVersion(ctx, hasDevelopment, rb, nil, false)
	}

	timestampFile := android.PathForModuleOut(ctx, "update_or_freeze_api_"+version+".timestamp")
	rb.SetPhonyOutput()
	// explicitly don't touch timestamp, so that the command can be run repeatedly
	rb.Command().Text("true").ImplicitOutput(timestampFile)

	rb.Build("dump_aidl_api_"+m.ModuleBase.Name()+"_"+version, actionWord+" AIDL API dump version "+version+" for "+m.ModuleBase.Name()+" (see "+targetDir+")")
	return timestampFile
}

type deps struct {
	preprocessed android.Paths
	implicits    android.Paths
	imports      []string
}

// calculates import flags(-I) from deps.
// When the target is ToT, use ToT of imported interfaces. If not, we use "current" snapshot of
// imported interfaces.
func getDeps(ctx android.ModuleContext, versionedImports map[string]string) deps {
	var deps deps
	if m, ok := ctx.Module().(*aidlInterface); ok {
		deps.imports = append(deps.imports, m.properties.Include_dirs...)
	}
	ctx.VisitDirectDeps(func(dep android.Module) {
		switch ctx.OtherModuleDependencyTag(dep).(type) {
		case importInterfaceDepTag:
			iface := dep.(*aidlInterface)
			if version, ok := versionedImports[iface.BaseModuleName()]; ok {
				if iface.preprocessed[version] == nil {
					ctx.ModuleErrorf("can't import %v's preprocessed(version=%v)", iface.BaseModuleName(), version)
				}
				deps.preprocessed = append(deps.preprocessed, iface.preprocessed[version])
			}
		case interfaceDepTag:
			iface := dep.(*aidlInterface)
			deps.imports = append(deps.imports, iface.properties.Include_dirs...)
		case apiDepTag:
			apiInfo := expectOtherModuleProvider(ctx, dep, aidlApiProvider)
			// add imported module's checkapiTimestamps as implicits to make sure that imported apiDump is up-to-date
			deps.implicits = append(deps.implicits, apiInfo.CheckApiTimestamps...)
			deps.implicits = append(deps.implicits, apiInfo.CheckHashTimestamps...)
			deps.implicits = append(deps.implicits, apiInfo.HasDevelopment)
		case interfaceHeadersDepTag:
			aidlLibraryInfo, ok := android.OtherModuleProvider(ctx, dep, aidl_library.AidlLibraryProvider)
			if !ok {
				ctx.PropertyErrorf("headers", "module %v does not provide AidlLibraryInfo", dep.Name())
				return
			}
			deps.implicits = append(deps.implicits, aidlLibraryInfo.Hdrs.ToList()...)
			deps.imports = append(deps.imports, android.Paths(aidlLibraryInfo.IncludeDirs.ToList()).Strings()...)
		}
	})
	return deps
}

func (m *aidlInterface) checkApi(ctx android.ModuleContext, oldDump, newDump apiDump, checkApiLevel string, messageFile android.Path) android.WritablePath {
	newVersion := newDump.dir.Base()
	timestampFile := android.PathForModuleOut(ctx, "checkapi_"+newVersion+".timestamp")

	// --checkapi(old,new) should use imports for "new"
	deps := getDeps(ctx, m.getImports(newDump.version))
	var implicits android.Paths
	implicits = append(implicits, deps.implicits...)
	implicits = append(implicits, deps.preprocessed...)
	implicits = append(implicits, oldDump.files...)
	implicits = append(implicits, newDump.files...)
	implicits = append(implicits, messageFile)

	var optionalFlags []string
	if m.properties.Stability != nil {
		optionalFlags = append(optionalFlags, "--stability", *m.properties.Stability)
	}
	optionalFlags = append(optionalFlags, wrap("-p", deps.preprocessed.Strings(), "")...)

	ctx.Build(pctx, android.BuildParams{
		Rule:      aidlCheckApiRule,
		Implicits: implicits,
		Output:    timestampFile,
		Args: map[string]string{
			"optionalFlags": strings.Join(optionalFlags, " "),
			"imports":       strings.Join(wrap("-I", deps.imports, ""), " "),
			"old":           oldDump.dir.String(),
			"new":           newDump.dir.String(),
			"messageFile":   messageFile.String(),
			"checkApiLevel": checkApiLevel,
		},
	})
	return timestampFile
}

func (m *aidlInterface) checkCompatibility(ctx android.ModuleContext, oldDump, newDump apiDump) android.WritablePath {
	messageFile := android.PathForSource(ctx, "system/tools/aidl/build/message_check_compatibility.txt")
	return m.checkApi(ctx, oldDump, newDump, "compatible", messageFile)
}

func (m *aidlInterface) checkEquality(ctx android.ModuleContext, oldDump apiDump, newDump apiDump) android.WritablePath {
	// Use different messages depending on whether platform SDK is finalized or not.
	// In case when it is finalized, we should never allow updating the already frozen API.
	// If it's not finalized, we let users to update the current version by invoking
	// `m <name>-update-api`.
	var messageFile android.SourcePath
	if m.isFrozen() {
		messageFile = android.PathForSource(ctx, "system/tools/aidl/build/message_check_equality_frozen.txt")
	} else {
		messageFile = android.PathForSource(ctx, "system/tools/aidl/build/message_check_equality.txt")
	}
	formattedMessageFile := android.PathForModuleOut(ctx, "message_check_equality.txt")
	rb := android.NewRuleBuilder(pctx, ctx)
	rb.Command().Text("sed").Flag(" s/%s/" + m.ModuleBase.Name() + "/g ").Input(messageFile).Text(" > ").Output(formattedMessageFile)
	rb.Build("format_message_"+m.ModuleBase.Name(), "")

	return m.checkApi(ctx, oldDump, newDump, "equal", formattedMessageFile)
}

func (m *aidlInterface) checkIntegrity(ctx android.ModuleContext, dump apiDump) android.WritablePath {
	version := dump.dir.Base()
	timestampFile := android.PathForModuleOut(ctx, "checkhash_"+version+".timestamp")
	messageFile := android.PathForSource(ctx, "system/tools/aidl/build/message_check_integrity.txt")

	var implicits android.Paths
	implicits = append(implicits, dump.files...)
	implicits = append(implicits, dump.hashFile.Path())
	implicits = append(implicits, messageFile)
	ctx.Build(pctx, android.BuildParams{
		Rule:      aidlVerifyHashRule,
		Implicits: implicits,
		Output:    timestampFile,
		Args: map[string]string{
			"apiDir":      dump.dir.String(),
			"version":     versionForHashGen(version),
			"hashFile":    dump.hashFile.Path().String(),
			"messageFile": messageFile.String(),
		},
	})
	return timestampFile
}

// Get the `latest` versions of the imported AIDL interfaces. If an interface is frozen, this is the
// last frozen version, if it is `frozen: false` this is the last frozen version + 1, if `frozen` is
// not set this is the last frozen version because we don't know if there are changes or not to the
// interface.
// map["foo":"3", "bar":1]
func (m *aidlInterface) getLatestImportVersions(ctx android.ModuleContext) map[string]string {
	var latest_versions = make(map[string]string)
	ctx.VisitDirectDeps(func(dep android.Module) {
		switch ctx.OtherModuleDependencyTag(dep).(type) {
		case apiDepTag:
			intf := dep.(*aidlInterface)
			if intf.hasVersion() {
				if intf.properties.Frozen == nil || intf.isFrozen() {
					latest_versions[intf.ModuleBase.Name()] = intf.latestVersion()
				} else {
					latest_versions[intf.ModuleBase.Name()] = intf.nextVersion()
				}
			} else {
				latest_versions[intf.ModuleBase.Name()] = "1"
			}
		}
	})
	return latest_versions
}

func (m *aidlInterface) checkForDevelopment(ctx android.ModuleContext, latestVersionDump *apiDump, totDump apiDump) android.Path {
	hasDevPath := android.PathForModuleOut(ctx, "has_development")
	rb := android.NewRuleBuilder(pctx, ctx)
	rb.Command().Text("rm -f " + hasDevPath.String())
	if latestVersionDump != nil {
		current_imports := m.getImports(currentVersion)
		versions := m.getVersions()
		last_frozen_imports := m.getImports(versions[len(versions)-1])
		var latest_versions = m.getLatestImportVersions(ctx)
		// replace any "latest" version with the version number from latest_versions
		for import_name, latest_version := range current_imports {
			if latest_version == "latest" {
				current_imports[import_name] = latest_versions[import_name]
			}
		}
		for import_name, latest_version := range last_frozen_imports {
			if latest_version == "latest" {
				last_frozen_imports[import_name] = latest_versions[import_name]
			}
		}
		different_imports := false
		if !reflect.DeepEqual(current_imports, last_frozen_imports) {
			if m.isFrozen() {
				ctx.ModuleErrorf("This interface is 'frozen: true' but the imports have changed. Set 'frozen: false' to allow changes: \n Version %s imports: %s\n Version %s imports: %s\n",
					currentVersion,
					fmt.Sprint(current_imports),
					versions[len(versions)-1],
					fmt.Sprint(last_frozen_imports))
				return hasDevPath
			}
			different_imports = true
		}
		// checkapi(latest, tot) should use imports for nextVersion(=tot)
		hasDevCommand := rb.Command()
		if !different_imports {
			hasDevCommand.BuiltTool("aidl").FlagWithArg("--checkapi=", "equal")
			if m.properties.Stability != nil {
				hasDevCommand.FlagWithArg("--stability ", *m.properties.Stability)
			}
			deps := getDeps(ctx, m.getImports(m.nextVersion()))
			hasDevCommand.
				FlagForEachArg("-I", deps.imports).Implicits(deps.implicits).
				FlagForEachInput("-p", deps.preprocessed).
				Text(latestVersionDump.dir.String()).Implicits(latestVersionDump.files).
				Text(totDump.dir.String()).Implicits(totDump.files)
			if m.isExplicitlyUnFrozen() {
				// Throw an error if checkapi returns with no differences
				msg := fmt.Sprintf("echo \"Interface %s can not be marked \\`frozen: false\\` if there are no changes "+
					"or different imports between the current version and the last frozen version.\"", m.ModuleBase.Name())
				hasDevCommand.
					Text(fmt.Sprintf("2> /dev/null && %s && exit -1 || echo $? >", msg)).Output(hasDevPath)
			} else {
				// if is explicitly frozen
				if m.isFrozen() {
					// Throw an error if checkapi returns WITH differences
					msg := fmt.Sprintf("echo \"Interface %s can not be marked \\`frozen: true\\` because there are changes "+
						"between the current version and the last frozen version.\"", m.ModuleBase.Name())
					hasDevCommand.
						Text(fmt.Sprintf("2> /dev/null || ( %s && exit -1) && echo 0 >", msg)).Output(hasDevPath)
				} else {
					hasDevCommand.
						Text("2> /dev/null; echo $? >").Output(hasDevPath)
				}

			}
		} else {
			// We know there are different imports which means has_development must be true
			hasDevCommand.Text("echo 1 >").Output(hasDevPath)
		}
	} else {
		rb.Command().Text("echo 1 >").Output(hasDevPath)
	}
	rb.Build("check_for_development", "")
	return hasDevPath
}

func (m *aidlInterface) generateApiBuildActions(ctx android.ModuleContext) {
	if proptools.Bool(m.properties.Unstable) {
		android.SetProvider(ctx, aidlApiProvider, aidlApiInfo{
			Unstable: true,
		})
		return
	}

	// An API dump is created from source and it is compared against the API dump of the
	// 'current' (yet-to-be-finalized) version. By checking this we enforce that any change in
	// the AIDL interface is gated by the AIDL API review even before the interface is frozen as
	// a new version.
	totApiDump := m.createApiDumpFromSource(ctx)
	currentApiDir := android.ExistentPathForSource(ctx, ctx.ModuleDir(), m.apiDir(), currentVersion)
	var checkApiTimestamps android.Paths
	var currentApiDump apiDump
	if currentApiDir.Valid() {
		currentApiDump = apiDump{
			version:  nextVersion(m.getVersions()),
			dir:      currentApiDir.Path(),
			files:    ctx.Glob(filepath.Join(currentApiDir.Path().String(), "**/*.aidl"), nil),
			hashFile: android.ExistentPathForSource(ctx, ctx.ModuleDir(), m.apiDir(), currentVersion, ".hash"),
		}
		checked := m.checkEquality(ctx, currentApiDump, totApiDump)
		checkApiTimestamps = append(checkApiTimestamps, checked)
	} else {
		// The "current" directory might not exist, in case when the interface is first created.
		// Instruct user to create one by executing `m <name>-update-api`.
		rb := android.NewRuleBuilder(pctx, ctx)
		rb.Command().Text(fmt.Sprintf(`echo "API dump for the current version of AIDL interface %s does not exist."`, m.ModuleBase.Name()))
		rb.Command().Text(fmt.Sprintf(`echo "Run the command \"m %s-update-api\" or add \"unstable: true\" to the build rule for the interface if it does not need to be versioned"`, m.ModuleBase.Name()))
		// This file will never be created. Otherwise, the build will pass simply by running 'm; m'.
		alwaysChecked := android.PathForModuleOut(ctx, "checkapi_current.timestamp")
		rb.Command().Text("false").ImplicitOutput(alwaysChecked)
		rb.Build("check_current_aidl_api", "")
		checkApiTimestamps = append(checkApiTimestamps, alwaysChecked)
	}

	// Also check that version X is backwards compatible with version X-1.
	// "current" is checked against the latest version.
	var dumps []apiDump
	for _, ver := range m.getVersions() {
		apiDir := filepath.Join(ctx.ModuleDir(), m.apiDir(), ver)
		apiDirPath := android.ExistentPathForSource(ctx, apiDir)
		if apiDirPath.Valid() {
			hashFilePath := filepath.Join(apiDir, ".hash")
			dump := apiDump{
				version:  ver,
				dir:      apiDirPath.Path(),
				files:    ctx.Glob(filepath.Join(apiDirPath.String(), "**/*.aidl"), nil),
				hashFile: android.ExistentPathForSource(ctx, hashFilePath),
			}
			if !dump.hashFile.Valid() {
				// We should show the source path of hash_gen because aidl_hash_gen cannot be built due to build error.
				cmd := fmt.Sprintf(`(croot && system/tools/aidl/build/hash_gen.sh %s %s %s)`, apiDir, versionForHashGen(ver), hashFilePath)
				ctx.ModuleErrorf("A frozen aidl_interface must have '.hash' file, but %s-V%s doesn't have it. Use the command below to generate a hash (DANGER: this should not normally happen. If an interface is changed downstream, it may cause undefined behavior, test failures, unexplained weather conditions, or otherwise broad malfunction of society. DO NOT RUN THIS COMMAND TO BREAK APIS. DO NOT!).\n%s\n",
					m.ModuleBase.Name(), ver, cmd)
			}
			dumps = append(dumps, dump)
		} else if ctx.Config().AllowMissingDependencies() {
			ctx.AddMissingDependencies([]string{apiDir})
		} else {
			ctx.ModuleErrorf("API version %s path %s does not exist", ver, apiDir)
		}
	}
	var latestVersionDump *apiDump
	if len(dumps) >= 1 {
		latestVersionDump = &dumps[len(dumps)-1]
	}
	if currentApiDir.Valid() {
		dumps = append(dumps, currentApiDump)
	}
	var checkHashTimestamps android.Paths
	for i := range dumps {
		if dumps[i].hashFile.Valid() {
			checkHashTimestamp := m.checkIntegrity(ctx, dumps[i])
			checkHashTimestamps = append(checkHashTimestamps, checkHashTimestamp)
		}

		if i == 0 {
			continue
		}
		checked := m.checkCompatibility(ctx, dumps[i-1], dumps[i])
		checkApiTimestamps = append(checkApiTimestamps, checked)
	}

	// Check for active development on the unfrozen version
	hasDevelopment := m.checkForDevelopment(ctx, latestVersionDump, totApiDump)

	// API dump from source is updated to the 'current' version. Triggered by `m <name>-update-api`
	updateApiTimestamp := m.makeApiDumpAsVersion(ctx, hasDevelopment, totApiDump, currentVersion)
	ctx.Phony(m.ModuleBase.Name()+"-update-api", updateApiTimestamp)

	// API dump from source is frozen as the next stable version. Triggered by `m <name>-freeze-api`
	nextVersion := m.nextVersion()
	freezeApiTimestamp := m.makeApiDumpAsVersion(ctx, hasDevelopment, totApiDump, nextVersion)
	ctx.Phony(m.ModuleBase.Name()+"-freeze-api", freezeApiTimestamp)

	nextApiDir := filepath.Join(ctx.ModuleDir(), m.apiDir(), nextVersion)
	if android.ExistentPathForSource(ctx, nextApiDir).Valid() {
		ctx.ModuleErrorf("API Directory exists for version %s path %s exists, but it is not specified in versions field.", nextVersion, nextApiDir)
	}

	android.SetProvider(ctx, aidlApiProvider, aidlApiInfo{
		Unstable:            false,
		CheckApiTimestamps:  checkApiTimestamps,
		CheckHashTimestamps: checkHashTimestamps,
		FreezeApiTimestamp:  freezeApiTimestamp,
		HasDevelopment:      hasDevelopment,
	})
}

func versionForHashGen(ver string) string {
	// aidlHashGen uses the version before current version. If it has never been frozen, return 'latest-version'.
	verInt, _ := strconv.Atoi(ver)
	if verInt > 1 {
		return strconv.Itoa(verInt - 1)
	}
	return "latest-version"
}

func init() {
	android.RegisterParallelSingletonType("aidl-freeze-api", freezeApiSingletonFactory)
}

func freezeApiSingletonFactory() android.Singleton {
	return &freezeApiSingleton{}
}

type freezeApiSingleton struct{}

func (f *freezeApiSingleton) GenerateBuildActions(ctx android.SingletonContext) {
	ownersToFreeze := strings.Fields(ctx.Config().Getenv("AIDL_FREEZE_OWNERS"))
	var files android.Paths
	ctx.VisitAllModuleProxies(func(module android.ModuleProxy) {
		commonInfo := android.OtherModulePointerProviderOrDefault(ctx, module, android.CommonModuleInfoProvider)
		if !commonInfo.Enabled {
			return
		}
		if apiInfo, ok := android.OtherModuleProvider(ctx, module, aidlApiProvider); ok {
			if apiInfo.Unstable {
				return
			}
			var shouldBeFrozen bool
			if len(ownersToFreeze) > 0 {
				shouldBeFrozen = android.InList(commonInfo.Owner, ownersToFreeze)
			} else {
				shouldBeFrozen = commonInfo.Owner == ""
			}
			if shouldBeFrozen {
				files = append(files, apiInfo.FreezeApiTimestamp)
			}
		}
	})
	ctx.Phony("aidl-freeze-api", files...)
}
