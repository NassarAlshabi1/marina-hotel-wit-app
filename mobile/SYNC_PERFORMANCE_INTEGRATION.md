# Performance Monitoring Screen Integration Guide

## Overview
The `SyncPerformanceScreen` provides comprehensive monitoring and analytics for your Google Drive sync operations.

## Features
- 📊 Real-time performance statistics
- 📈 Duration trend charts
- 🎯 Success rate visualization
- 📝 Detailed sync history
- 🔄 Pull-to-refresh support
- 🌍 Full RTL Arabic support

## Quick Integration

### Option 1: Add to Settings/Debug Menu

```dart
// In your settings or debug menu screen
ListTile(
  leading: const Icon(Icons.analytics),
  title: const Text('أداء المزامنة'),
  subtitle: const Text('عرض إحصائيات ومخططات الأداء'),
  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SyncPerformanceScreen(),
      ),
    );
  },
)
```

### Option 2: Add to Dashboard as Quick Action

```dart
// In dashboard_screen.dart, add to action buttons:
IconButton(
  icon: const Icon(Icons.analytics_outlined),
  tooltip: 'أداء المزامنة',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SyncPerformanceScreen(),
      ),
    );
  },
)
```

### Option 3: Add to Smart Sync Card

In `SmartSyncDashboardCard` widget:

```dart
// Add a text button at the bottom of the card
TextButton.icon(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SyncPerformanceScreen(),
      ),
    );
  },
  icon: const Icon(Icons.analytics, size: 16),
  label: const Text('عرض تفاصيل الأداء'),
)
```

## Example: Adding to App Drawer

```dart
// In your main drawer/navigation drawer
ListTile(
  leading: const Icon(Icons.analytics),
  title: const Text('أداء المزامنة'),
  onTap: () {
    Navigator.pop(context); // Close drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SyncPerformanceScreen(),
      ),
    );
  },
),
```

## Import Required

```dart
import 'package:marina_hotel_mobile/screens/sync_performance_screen.dart';
```

## Testing

To test the screen with sample data, ensure you have some sync operations recorded:

```dart
// The screen will automatically load data from SyncPerformanceTracker
// Sample data is recorded during actual sync operations
// For testing, you can manually trigger a sync from the dashboard
```

## Empty State

The screen gracefully handles empty states with a user-friendly message when no sync data is available yet.

## Customization

The screen uses your app's theme automatically. Charts use:
- Blue for duration trends
- Green for successful syncs
- Red for failed syncs
- Orange for data size metrics
- Purple for cache syncs

## Performance Metrics Displayed

1. **Statistics Cards**
   - Average sync duration
   - Success rate
   - Average data size
   - Total sync count

2. **Duration Chart**
   - Line chart showing last 10 sync durations
   - Visual trend analysis

3. **Success Rate Chart**
   - Pie chart showing success vs failure ratio
   - Large percentage display

4. **Recent Syncs List**
   - Timestamp
   - Duration
   - Records downloaded
   - Data size
   - Error messages (for failures)
   - Sync type badge (full/delta/cache)

## Advanced Usage

### Programmatic Navigation with Arguments

```dart
// Navigate and auto-refresh
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const SyncPerformanceScreen(),
  ),
).then((_) {
  // Callback after screen is closed
  print('Performance screen closed');
});
```

### Deep Link Support (Optional)

If your app uses route names:

```dart
// In your MaterialApp routes
routes: {
  '/sync-performance': (context) => const SyncPerformanceScreen(),
  // ... other routes
}

// Navigate using named route
Navigator.pushNamed(context, '/sync-performance');
```
