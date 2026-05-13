/// Re-export of key-decoding functions for external consumers / tests.
library;

export '../config/api_config.dart'
    show
        kDefaultUniversalKey,
        splitUniversalKey,
        extractApiKey,
        decodeMiddlewareBase,
        middlewareUrl;
