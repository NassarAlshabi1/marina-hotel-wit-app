class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1',
  );
  // TODO: Wire actual API v1 in next phase.

  static String dittoAppId = const String.fromEnvironment(
    'DITTO_APP_ID',
    defaultValue: '1507d904-d3ed-4ac3-824c-249c18170eee',
  );

  static String dittoPlaygroundToken = const String.fromEnvironment(
    'DITTO_PLAYGROUND_TOKEN',
    defaultValue: 'dbae5191-2cb5-4fb5-8aca-9f9d85e0409a',
  );

  static String dittoApiToken = const String.fromEnvironment(
    'DITTO_API_TOKEN',
    defaultValue: 'Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO',
  );

  static String dittoCloudWebhook = const String.fromEnvironment(
    'DITTO_CLOUD_WEBHOOK',
    defaultValue: 'https://i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee',
  );

  static bool dittoUsePlayground = const bool.fromEnvironment(
    'DITTO_USE_PLAYGROUND',
    defaultValue: true,
  );
}
