import 'package:uuid/uuid.dart';

/// Client-side identifier generation.
///
/// Two shapes are used, deliberately different (DESIGN §5.2, §5.3):
///
/// * **UUIDv7** for business rows. Time-ordered, so SQLite primary-key
///   inserts stay sequential and index pages stay dense, and so a local id
///   still sorts close to creation time when it is later referenced in logs.
/// * **UUIDv4** for `op_log.op_id` and `device_meta.device_id`. Neither needs
///   to be time-ordered; v4 gives a uniform random 122 bits with no
///   timestamp leakage, which is what an idempotency key and a stable device
///   identity both want.
///
/// Instances are cheap and stateless, so a single const instance is shared.
const _uuid = Uuid();

/// A fresh time-ordered id for a business row.
String newEntityId() => _uuid.v7();

/// A fresh random id for an op-log entry (the idempotency key).
String newOpId() => _uuid.v4();

/// A fresh random id for this install's device identity.
String newDeviceId() => _uuid.v4();
