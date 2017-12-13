Jsonnet is a domain specific configuration language that helps you define JSON data.
http://jsonnet.org/

In hako, you can use Jsonnet format for defining applications.

# External variables
Jsonnet provide a way to refer external variables by `std.extVar(x)`.
http://jsonnet.org/docs/stdlib.html#ext_vars

## appId
`std.extVar('appId')` returns application id of the definition.

### Example
```
% cat awesome-app.jsonnet
{
  id: std.extVar('appId'),
}
% hako show-definition awesome-app.jsonnet
---
id: awesome-app
```

# Native functions
Jsonnet provide a way to refer native functions by `std.native(x)`.

## provide.$NAME
`std.native('provide.$NAME')` returns a function which returns a corresponding EnvProvider.

### Example
```
% cat awesome-app.env
username=eagletmt
% cat awesome-app.yml
password: hako
% cat awesome-app.jsonnet
local provideFromFile(name) = std.native('provide.file')(std.toString({ path: 'awesome-app.env' }), name);
local provideFromYaml(name) = std.native('provide.yaml')(std.toString({ path: 'awesome-app.yml' }), name);

{
  username: provideFromFile('username'),
  password: provideFromYaml('password'),
}
% hako show-definition --expand awesome-app.jsonnet
---
password: hako
username: eagletmt
```
