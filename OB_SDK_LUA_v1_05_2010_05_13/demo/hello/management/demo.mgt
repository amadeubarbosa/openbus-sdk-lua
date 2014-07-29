System {
  id = "HelloWorld",
  description = "Demo Hello World",
}

SystemDeployment {
  id = "HelloService",
  system = "HelloWorld",
  description = "Serviço do Hello World",
  certificate = "HelloService.crt",
}

Interface {
  id = "IDL:demoidl/hello/IHello:1.0"
}

Grant {
  id = "HelloService",
  interfaces = {
    "IDL:demoidl/hello/IHello:1.0",
  }
}
