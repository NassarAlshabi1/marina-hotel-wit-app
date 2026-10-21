// Backward-compatible export for callers in the services layer.
// All hotel-day and night calculations are implemented in the canonical
// utility engine, which delegates night counts to `Time.nightsWithCutoff`.
// Keeping this export avoids a second implementation drifting from the
// strict 14:01 hotel-day boundary.
export '../utils/hotel_time_engine.dart';
