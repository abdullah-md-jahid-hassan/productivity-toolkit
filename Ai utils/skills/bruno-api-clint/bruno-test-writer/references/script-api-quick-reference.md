# Bruno Script API Quick Reference

Use these helpers in generated scripts and tests.

## Request helpers

- `req.getUrl()` gets the current URL.
- `req.setUrl(url)` changes the URL in a pre-request script.
- `req.getMethod()` gets the HTTP method.
- `req.setMethod(method)` changes the method in a pre-request script.
- `req.getHeader(name)` gets a request header.
- `req.setHeader(name, value)` sets a request header.
- `req.getBody()` gets the request body.
- `req.setBody(body)` sets the request body in a pre-request script.

## Response helpers

- `res.getStatus()` gets the status code.
- `res.getStatusText()` gets the status text.
- `res.getHeader(name)` gets a response header.
- `res.getHeaders()` gets response headers.
- `res.getBody()` gets the parsed response body.
- `res.getResponseTime()` gets response time.

## Variable helpers

Bruno variable precedence is runtime, request, folder, collection, then environment.

- `bru.getVar(key)` gets a variable using precedence.
- `bru.setVar(key, value)` stores a runtime variable.
- `bru.deleteVar(key)` deletes a runtime variable.
- `bru.getEnvVar(key)` gets an environment variable.
- `bru.setEnvVar(key, value)` sets an environment variable for the active run.
- `bru.getSecretVar(key)` reads a secret variable when available.

## Runner helpers

- `bru.runner.setNextRequest(requestName)` controls the next request.
- `bru.runner.skipRequest()` skips a request.
- `bru.runner.stopExecution()` stops the run.

## Guidance

- Prefer `bru.setVar` for values needed later in the same run.
- Prefer environment variables for stable configuration such as `baseUrl`.
- Treat tokens, API keys, cookies, and credentials as secrets.
- Avoid logging sensitive values, and never copy real secret or PII values out of a response into a generated test; assert on shape instead.
- `bru.setEnvVar` and `bru.runner.stopExecution`/`setNextRequest` change shared run state. Use them only when the flow needs it, and prefer `bru.setVar` (runtime scope) for values passed between requests.
