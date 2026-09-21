# Bruno Testing Patterns

Use these snippets when creating Bruno tests.

## Status code

```javascript
test("should return success", function () {
  expect(res.getStatus()).to.equal(200);
});
```

## Response body object

```javascript
test("should return an object", function () {
  const body = res.getBody();
  expect(body).to.be.an("object");
});
```

## Required fields

```javascript
test("should include required fields", function () {
  const body = res.getBody();
  expect(body).to.have.property("id");
  expect(body).to.have.property("name");
  expect(body).to.have.property("email");
});
```

## Array response

```javascript
test("should return an array of records", function () {
  const body = res.getBody();
  expect(body).to.be.an("array");
  body.forEach((item) => {
    expect(item).to.have.property("id");
  });
});
```

## Conditional status handling

```javascript
test("should validate known response states", function () {
  const status = res.getStatus();
  const body = res.getBody();

  if (status === 200) {
    expect(body).to.have.property("data");
  } else if (status === 404) {
    expect(body).to.have.property("error");
    expect(body.error).to.have.property("message");
  } else {
    throw new Error(`Unexpected status code: ${status}`);
  }
});
```

## Error response structure

```javascript
test("should validate error response structure", function () {
  const status = res.getStatus();
  if (status >= 400) {
    const body = res.getBody();
    expect(body).to.have.property("error");
    expect(body.error).to.have.property("message");
    expect(body.error.message).to.be.a("string");
  }
});
```

## Header checks

```javascript
test("should return JSON", function () {
  expect(res.getHeader("content-type")).to.contain("application/json");
});
```

## Response time

Only add this when the user gives a threshold or the collection has an existing convention.

```javascript
test("should respond within threshold", function () {
  expect(res.getResponseTime()).to.be.lessThan(1000);
});
```

## Save values for later requests

```javascript
test("should save token", function () {
  const body = res.getBody();
  expect(body).to.have.property("token");
  expect(body.token).to.not.be.empty;
  bru.setVar("token", body.token);
});
```

## Avoid these patterns

- Exact full-body equality for dynamic responses.
- Logging `Authorization`, tokens, API keys, cookies, or secrets.
- Assuming arrays always have a fixed length unless the API contract says so.
- Setting global variables when a runtime variable is enough.
