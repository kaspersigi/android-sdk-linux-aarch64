package hello.world;

interface IHello {
    // Have the service log a message for us
    void LogMessage(String message);
    // Get a "hello world" message from the service
    String getMessage();
}
