# Pulled in transitively by `mcp`. Opts out of MultiJSON, which json-schema
# itself deprecates in favor of stdlib JSON.
JSON::Validator.use_multi_json = false if defined?(JSON::Validator)
