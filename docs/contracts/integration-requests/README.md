# Integration requests

A packet that needs a change in an integration-owned file does not edit it. It writes
the exact patch here as `<packet>.md` and keeps building against a local fixture.

Integration-owned files: `src/app.ts`, `src/api/router.ts`, `src/api/trpc.ts`,
`src/config.ts`, `src/domain/**`, `src/core/projections/ReadModel.ts`, `lib/main.dart`,
`pubspec.yaml`, `bun.lock`, `lib/shared/screens/home/home.dart`, bottom navigation.

Each request states: the file, the exact diff, why it cannot be avoided, and what
breaks if it is not applied.
