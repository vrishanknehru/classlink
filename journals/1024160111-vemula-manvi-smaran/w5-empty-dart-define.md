# Week 5 : Release App Pointed at an Empty Server Address

# Build Time Settings

## Error:

A release APK built in GitHub Actions without the server
variable set would try to call an empty address instead
of the local fallback.

## Relevant Context

The workflow passes the address into the build:

``` shell
flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL"
```

and the app read it with a default:

``` dart
const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
)
```

## Key Observation

When the variable is unset, the shell still passes
`API_BASE_URL=` with an empty value. The define exists,
so `defaultValue` never applies.

## Solution

Treat empty the same as missing:

``` dart
apiBaseUrl: _trimSlash(
  const String.fromEnvironment('API_BASE_URL').isEmpty
      ? localApi
      : const String.fromEnvironment('API_BASE_URL'),
),
```

and print a warning in the workflow when the variable is
not set.

**Because**

`String.fromEnvironment` falls back only when the name was
never defined. An empty string counts as defined.
