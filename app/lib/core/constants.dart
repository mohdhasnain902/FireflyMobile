/// Application-wide constants.
///
/// Values that change per build or per user (base URL, API key) are *not*
/// here — they live in runtime configuration (see the `sync` module) because
/// they must be editable without a rebuild.
library;

/// Product name shown in the OS launcher and app bar.
const String kAppName = 'Firefly III';

/// Default currency code used until the user's Firefly preference is pulled.
const String kDefaultCurrencyCode = 'EUR';

/// Maximum number of operations pushed/pulled in a single sync batch.
///
/// Keeps request payloads small and bounds the blast radius of one failed
/// request (DESIGN §11: SQLite lock contention during bulk import).
const int kSyncBatchSize = 50;
