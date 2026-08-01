# app

The composition root. It owns the two things that can only exist once the whole
app is assembled: **navigation** and the **connectors** that bridge `business`
state to `ui` widgets.

```text
app/lib/
├── main.dart          # entry point — runEnv(await Environment.prod())
├── dev.dart           # entry point — runEnv(await Environment.dev()) (reads .env)
├── run_env.dart       # bootstrap: store, dependencies, router, window, logging
├── app.dart           # AppConnector: MaterialApp.router + theme/locale/overlays
├── connectors/        # @RoutePage() StoreConnectors — one per screen
├── navigation/        # AppRouter (+ generated app_router.gr.dart), GoAction
├── dialogs/           # ExceptionDialog — UserException → dialog
└── common/            # validators shared by the connectors
```

Run the dev entry point with `-t`:

```bash
flutter run -t lib/dev.dart      # Environment.dev()
flutter run                      # lib/main.dart → Environment.prod()
```

Scaffolding belongs to [`frx`](../tools/README.md) — `frx add-page` writes the
page, the connector and the `AutoRoute` entry; `frx add-nav` wires one screen's
hop to another. Nothing here is meant to be wired by hand.

## .env

Only the **dev** entry point reads it, and only outside release mode
([`business/lib/environment.dart`](../business/lib/environment.dart)). It is
loaded with `isOptional: true`, so a missing file falls back to the built-in
`baseUrl` rather than failing.

1. Create `app/.env`:

   ```bash
   BASE_URL=https://api.example.com
   ```

2. Declare it as an asset in [`app/pubspec.yaml`](pubspec.yaml) — `flutter_dotenv`
   reads it through the asset bundle, so an undeclared file is silently absent.
   The entry ships commented out:

   ```yaml
   flutter:
     uses-material-design: true

     assets:
       - .env
   ```

`BASE_URL` is the only key read today (`dotenv.maybeGet('BASE_URL', …)`).
