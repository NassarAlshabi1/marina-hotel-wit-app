// Backward-compatible export for services that use the historical path.
// Hotel-day and night calculations are implemented by the canonical utility
// engine, which delegates night counts to Time.nightsWithCutoff.
export '../utils/hotel_time_engine.dart';
