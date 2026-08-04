# Marina Hotel Mobile - GitHub Copilot Instructions
# ==================================================

> **F4DD Last Updated:** 2026-08-03  
> **F4BB Maintainer:** Marina Hotel Dev Team  
> **F4A1 Project:** Marina Hotel Mobile (Flutter/Dart)  
> **F4F0 Status:** F534 **ACTIVE** F534

---

## F4C8 Table of Contents

1. [F4AF Overview](#-overview)
2. [F4B0 Project Context](#-project-context)
3. [F4D1 Coding Standards](#-coding-standards)
4. [F4E6 Architecture Guidelines](#-architecture-guidelines)
5. [F4BB Technology Stack](#-technology-stack)
6. [F4BC Code Review Focus Areas](#-code-review-focus-areas)
7. [F4BD Common Patterns](#-common-patterns)
8. [F4BE Anti-Patterns to Avoid](#-anti-patterns-to-avoid)
9. [F4BF Security Guidelines](#-security-guidelines)
10. [F4C0 Performance Guidelines](#-performance-guidelines)
11. [F4C1 Testing Guidelines](#-testing-guidelines)
12. [F4C2 Localization (RTL) Guidelines](#-localization-rtl-guidelines)

---

## F4AF Overview

This document provides **custom instructions** for **GitHub Copilot** when reviewing code in the **Marina Hotel Mobile** project. These instructions help Copilot understand our **project-specific conventions, architecture, and best practices**.

---

## F4B0 Project Context

### F469 About Marina Hotel Mobile

**Marina Hotel Mobile** is a **complete hotel management system** built with:
- **Flutter** (UI Framework)
- **Dart** (Programming Language)
- **Riverpod** (State Management)
- **Appwrite** (Backend Services)
- **Firebase** (Analytics, Crashlytics, Messaging)
- **SQLite (Drift)** (Local Database)

**Target Platforms:**
- Android (Primary)
- iOS (Secondary)
- Web (Future)

**Target Audience:**
- Hotel staff (Arabic-speaking)
- Hotel managers
- Administrators

**Key Features:**
- Room management
- Booking system
- Guest management
- Payment processing
- Reporting and analytics
- Offline-first capability
- RTL (Arabic) support

---

## F4D1 Coding Standards

### F469 General Standards

**Follow these standards when reviewing code:**

1. **Naming Conventions**
   - Use **lowerCamelCase** for variables and functions
   - Use **UpperCamelCase** (PascalCase) for classes and widgets
   - Use **SCREAMING_SNAKE_CASE** for constants
   - Use **descriptive names** (avoid abbreviations unless widely known)

2. **Code Formatting**
   - **2-space indentation** (no tabs)
   - **80-character line limit** (soft limit, 120 hard limit)
   - **Trailing commas** for multi-line lists/maps
   - **Consistent spacing** around operators and after commas

3. **Documentation**
   - **All public APIs** must have documentation comments
   - **Complex logic** must have inline comments
   - **TODO comments** should include issue references
   - **Avoid FIXME/XXX/HACK** comments in production code

4. **Type Safety**
   - **Always use explicit types** (avoid `var` and `dynamic`)
   - **Enable strict type checking** (null-safety)
   - **Use nullable types** (`?`) where appropriate
   - **Avoid type casts** (`as`) when possible

---

### F469 Flutter-Specific Standards

1. **Widget Structure**
   - **Small, focused widgets** (prefer composition over inheritance)
   - **Const constructors** where possible
   - **Proper key usage** for lists and animated widgets
   - **Avoid deep nesting** (use `Column`/`Row` wisely)

2. **State Management (Riverpod)**
   - **Use providers** for all state
   - **Prefer `StateNotifier`** for complex state
   - **Use `AsyncValue`** for async operations
   - **Avoid global state**

3. **Styling**
   - **Use `Theme`** for consistent styling
   - **Avoid hardcoded colors** (use `AppColors`)
   - **Use `TextStyle`** for consistent text styling
   - **RTL support** in all layouts

---

## F4E6 Architecture Guidelines

### F469 Project Structure

```
lib/
├── app/                    # App configuration
│   ├── app.dart           # Main app widget
│   ├── router.dart        # Route configuration
│   └── theme.dart         # App theme
├── core/                  # Core utilities
│   ├── constants/         # App constants
│   ├── errors/            # Error handling
│   ├── extensions/        # Dart extensions
│   ├── utils/             # Utility functions
│   └── widgets/           # Reusable widgets
├── features/              # Feature modules
│   ├── auth/              # Authentication
│   ├── bookings/          # Booking system
│   ├── guests/            # Guest management
│   ├── payments/          # Payment processing
│   ├── rooms/             # Room management
│   └── settings/          # App settings
├── models/                # Data models
│   ├── dtos/              # Data Transfer Objects
│   ├── entities/          # Business entities
│   └── repositories/      # Data repositories
├── providers/             # Riverpod providers
│   ├── auth_provider.dart
│   ├── booking_provider.dart
│   └── ...
├── services/              # External services
│   ├── appwrite/          # Appwrite integration
│   ├── firebase/          # Firebase integration
│   └── local_db/          # Local database (Drift)
└── main.dart              # App entry point
```

### F469 Architecture Principles

1. **Clean Architecture**
   - **Separation of concerns** (UI, Business Logic, Data)
   - **Dependency injection** (via Riverpod)
   - **Single Responsibility Principle** (SRP)
   - **Open/Closed Principle** (OCP)

2. **Data Flow**
   ```
   UI Layer (Widgets)
       ↓ (calls)
   Business Logic Layer (Providers/UseCases)
       ↓ (calls)
   Data Layer (Repositories/Services)
       ↓ (calls)
   External Services (Appwrite/Firebase)
   ```

3. **State Management**
   - **Riverpod** for all state management
   - **Providers** for dependency injection
   - **StateNotifier** for mutable state
   - **AsyncValue** for async state

4. **Data Access**
   - **Repository pattern** for data access
   - **DTOs** for API responses
   - **Entities** for business objects
   - **Mappers** to convert between DTOs and Entities

---

## F4BB Technology Stack

### F469 Core Technologies

| Technology | Purpose | Version |
|------------|---------|---------|
| **Flutter** | UI Framework | 3.35.7+ |
| **Dart** | Programming Language | 3.8.0+ |
| **Riverpod** | State Management | 2.6.1 |
| **Freezed** | Immutable Models | 3.2.5 |
| **JsonSerializable** | JSON Serialization | 6.14.0 |
| **Drift** | SQLite Database | 2.31.0 |
| **Appwrite** | Backend Services | 21.0.0 |
| **Firebase** | Analytics, Crashlytics | Latest |

### F469 Appwrite Services

**Marina Hotel uses Appwrite for:**
- **Authentication** (Users, Sessions)
- **Database** (Collections, Documents)
- **Storage** (File uploads)
- **Functions** (Cloud functions)
- **Realtime** (Live updates)

**Collections:**
- `users` - User accounts
- `guests` - Hotel guests
- `rooms` - Hotel rooms
- `bookings` - Room bookings
- `payments` - Payment records
- `settings` - App settings

### F469 Firebase Services

**Marina Hotel uses Firebase for:**
- **Analytics** - User behavior tracking
- **Crashlytics** - Crash reporting
- **Messaging** - Push notifications
- **Remote Config** - Feature flags
- **Performance** - Performance monitoring

---

## F4BC Code Review Focus Areas

### F469 High Priority (Must Review)

**Focus on these areas carefully:**

1. **Security**
   - F534 **Authentication/Authorization**
     - Proper user authentication
     - Role-based access control
     - Session management
   - F534 **Data Validation**
     - Input validation on all user inputs
     - Sanitization of database queries
     - Type safety in API calls
   - F534 **Sensitive Data**
     - No hardcoded API keys or secrets
     - Secure storage of sensitive data
     - Proper encryption of sensitive information

2. **Data Integrity**
   - F534 **Database Operations**
     - Proper transaction handling
     - Error handling for database operations
     - Data consistency across related tables
   - F534 **API Calls**
     - Proper error handling
     - Retry logic for failed requests
     - Loading states management

3. **Business Logic**
   - F534 **Booking System**
     - Room availability calculation
     - Pricing logic
     - Overbooking prevention
   - F534 **Payment Processing**
     - Payment validation
     - Refund logic
     - Payment status management

### F469 Medium Priority (Should Review)

1. **Performance**
   - Widget rebuilding optimization
   - State management efficiency
   - Database query optimization
   - Memory usage

2. **Code Quality**
   - Adherence to Dart/Flutter best practices
   - Proper use of Riverpod
   - Clean code principles
   - Consistent naming conventions

3. **Error Handling**
   - Comprehensive error handling
   - User-friendly error messages
   - Proper error logging
   - Graceful degradation

### F469 Low Priority (Nice to Review)

1. **Code Style**
   - Formatting consistency
   - Comment quality
   - Documentation completeness

2. **Testing**
   - Test coverage
   - Test structure
   - Edge case handling

---

## F4BD Common Patterns

### F469 Riverpod Patterns

**1. Provider Declaration**
```dart
// Good: Use final for providers
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});

// Bad: Avoid non-final providers
var authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
```

**2. StateNotifier Usage**
```dart
// Good: Proper state management
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authRepository) : super(AuthInitial());
  
  final AuthRepository _authRepository;
  
  Future<void> login(String email, String password) async {
    state = AuthLoading();
    try {
      final user = await _authRepository.login(email, password);
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }
}

// Bad: Avoid putting business logic in widgets
class LoginButton extends StatelessWidget {
  Future<void> login() async {
    // Business logic should be in a provider/notifier
  }
}
```

**3. Consumer Usage**
```dart
// Good: Use Consumer for specific providers
Consumer(
  builder: (context, ref, child) {
    final authState = ref.watch(authProvider);
    return authState.maybeWhen(
      authenticated: (user) => HomeScreen(user: user),
      orElse: () => LoginScreen(),
    );
  },
)

// Bad: Avoid watching many providers in one Consumer
Consumer(
  builder: (context, ref, child) {
    final authState = ref.watch(authProvider);
    final bookingState = ref.watch(bookingProvider);
    final roomState = ref.watch(roomProvider);
    // Too many providers in one Consumer
  },
)
```

### F469 Appwrite Patterns

**1. Client Initialization**
```dart
// Good: Singleton client
class AppwriteService {
  static final client = Client()
    ..setEndpoint('https://cloud.appwrite.io/v1')
    ..setProject('marina-hotel')
    ..setSelfSigned(status: true);
  
  static final databases = Databases(client);
  static final users = Users(client);
  // ...
}

// Bad: Multiple client instances
final client1 = Client();
final client2 = Client();
```

**2. Repository Usage**
```dart
// Good: Repository pattern
class BookingRepository {
  final Databases _databases;
  
  BookingRepository(this._databases);
  
  Future<List<Booking>> getBookings() async {
    try {
      final response = await _databases.listDocuments(
        databaseId: 'main',
        collectionId: 'bookings',
      );
      return response.documents.map(Booking.fromJson).toList();
    } catch (e) {
      throw BookingException('Failed to fetch bookings: $e');
    }
  }
}

// Bad: Direct Appwrite calls in widgets
class BookingList extends StatelessWidget {
  Future<List<Booking>> getBookings() async {
    final response = await Databases(client).listDocuments(...);
    // Direct Appwrite call in widget
  }
}
```

### F469 Freezed Patterns

**1. Model Definition**
```dart
// Good: Use Freezed for immutable models
part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class User with _$User {
  const factory User({
    required String id,
    required String name,
    required String email,
    String? avatarUrl,
    @Default(false) bool isActive,
  }) = _User;
  
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

// Bad: Manual model implementation
class User {
  final String id;
  final String name;
  // ... manual implementation
}
```

**2. JSON Serialization**
```dart
// Good: Use JsonSerializable with Freezed
@freezed
class Booking with _$Booking {
  const factory Booking._({
    required String id,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    required double totalPrice,
    @JsonKey(name: 'guest_id') required String guestId,
    @Default(BookingStatus.pending) BookingStatus status,
  }) = _Booking;
  
  factory Booking.fromJson(Map<String, dynamic> json) => _$BookingFromJson(json);
}

// Bad: Manual JSON serialization
class Booking {
  // ... manual fromJson/toJson
}
```

### F469 Drift (SQLite) Patterns

**1. Table Definition**
```dart
// Good: Use Drift for local database
class Rooms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get number => text().unique()();
  TextColumn get type => text()();
  RealColumn get price => real()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(false))();
  
  @override
  Set<Column> get primaryKey => {id};
}

// Bad: Avoid raw SQLite queries
final db = Database(...);
final results = await db.rawQuery('SELECT * FROM rooms');
```

**2. DAO Usage**
```dart
// Good: Use DAOs for database operations
@DriftAccessor(tables: [Rooms])
class RoomDao extends DatabaseAccessor<AppDatabase> with _$RoomDaoMixin {
  RoomDao(AppDatabase db) : super(db);
  
  Future<List<Room>> getAvailableRooms() async {
    final query = select(rooms)..where((t) => t.isAvailable.equals(true));
    return await query.get();
  }
  
  Future<int> insertRoom(RoomsCompanion room) async {
    return await into(rooms).insert(room);
  }
}

// Bad: Direct table access in widgets
class RoomList extends StatelessWidget {
  Future<List<Room>> getRooms() async {
    final db = AppDatabase();
    return await db.select(db.rooms).get();
  }
}
```

---

## F4BE Anti-Patterns to Avoid

### F469 Flutter Anti-Patterns

**1. Avoid setState in initState**
```dart
// Bad: setState in initState
@override
void initState() {
  super.initState();
  setState(() {}); // Avoid!
}

// Good: Use Future or WidgetsBinding
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Do something after first frame
  });
}
```

**2. Avoid Large Widgets**
```dart
// Bad: Large widget with too much logic
class LargeWidget extends StatelessWidget {
  // 500+ lines of code
  // Multiple responsibilities
  // Complex business logic
}

// Good: Split into smaller widgets
class LargeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HeaderWidget(),
        ContentWidget(),
        FooterWidget(),
      ],
    );
  }
}
```

**3. Avoid Direct Business Logic in Widgets**
```dart
// Bad: Business logic in widget
class BookingButton extends StatelessWidget {
  Future<void> createBooking() async {
    // Complex booking logic
    // Database operations
    // Validation
  }
}

// Good: Move logic to provider
class BookingButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingNotifier = ref.read(bookingProvider.notifier);
    return ElevatedButton(
      onPressed: bookingNotifier.createBooking,
      child: Text('Book Now'),
    );
  }
}
```

### F469 Riverpod Anti-Patterns

**1. Avoid Provider in Provider**
```dart
// Bad: Provider in provider
final userProvider = Provider<User>((ref) {
  final user = ref.watch(authProvider);
  return user;
});

// Good: Directly use the provider
final user = ref.watch(authProvider);
```

**2. Avoid Watching in initState**
```dart
// Bad: Watching in initState
@override
void initState() {
  super.initState();
  final user = ref.watch(authProvider); // Avoid!
}

// Good: Use read in initState
@override
void initState() {
  super.initState();
  final user = ref.read(authProvider); // OK
}
```

**3. Avoid Global Providers**
```dart
// Bad: Global provider
final globalUserProvider = Provider<User>((ref) => User());

// Good: Scoped provider
final userProvider = Provider<User>((ref) => ref.read(userRepositoryProvider).getUser());
```

### F469 Appwrite Anti-Patterns

**1. Avoid Hardcoded IDs**
```dart
// Bad: Hardcoded collection IDs
final bookings = await databases.listDocuments(
  databaseId: 'main',
  collectionId: 'bookings', // Hardcoded!
);

// Good: Use constants
final bookings = await databases.listDocuments(
  databaseId: AppConstants.databaseId,
  collectionId: AppConstants.bookingsCollection,
);
```

**2. Avoid Unhandled Errors**
```dart
// Bad: Unhandled errors
final response = await databases.listDocuments(...);
// No error handling!

// Good: Proper error handling
try {
  final response = await databases.listDocuments(...);
  return response.documents;
} catch (e) {
  throw BookingException('Failed to fetch bookings: $e');
}
```

**3. Avoid Direct Client Usage**
```dart
// Bad: Direct client usage
final client = Client();
final databases = Databases(client);

// Good: Use service/repository
final bookings = await bookingRepository.getBookings();
```

---

## F4BF Security Guidelines

### F469 Authentication & Authorization

**1. Proper Authentication**
```dart
// Good: Use Appwrite authentication
final session = await account.createEmailSession(
  email: email,
  password: password,
);

// Bad: Custom authentication
// Avoid implementing your own auth system
```

**2. Role-Based Access Control**
```dart
// Good: Check user roles
bool canAccessAdminFeatures(User user) {
  return user.roles.contains('admin');
}

// Bad: Hardcoded role checks
if (user.email == 'admin@example.com') { // Avoid!
  // Grant admin access
}
```

**3. Session Management**
```dart
// Good: Proper session handling
final currentSession = await account.getSession('current');
if (currentSession == null) {
  // Redirect to login
}

// Bad: Ignoring session state
// Always check session before allowing access
```

### F469 Data Validation

**1. Input Validation**
```dart
// Good: Validate all inputs
String validateEmail(String email) {
  if (!email.contains('@')) {
    throw ValidationException('Invalid email format');
  }
  return email;
}

// Bad: No validation
void saveUser(String email) {
  // Save without validation
}
```

**2. Database Query Sanitization**
```dart
// Good: Use parameterized queries
final query = select(rooms)..where((t) => t.id.equals(roomId));

// Bad: String concatenation in queries
final query = 'SELECT * FROM rooms WHERE id = $roomId'; // SQL Injection risk!
```

**3. Sensitive Data Handling**
```dart
// Good: Secure storage
final secureStorage = FlutterSecureStorage();
await secureStorage.write(key: 'auth_token', value: token);

// Bad: Insecure storage
final prefs = await SharedPreferences.getInstance();
await prefs.setString('auth_token', token); // Not secure!
```

### F469 API Security

**1. API Key Management**
```dart
// Good: Use environment variables
final apiKey = const String.fromEnvironment('API_KEY');

// Bad: Hardcoded API keys
const apiKey = 'sk-1234567890abcdef'; // Never do this!
```

**2. HTTPS Only**
```dart
// Good: Always use HTTPS
final client = Client()
  ..setEndpoint('https://api.example.com'); // HTTPS

// Bad: HTTP endpoints
final client = Client()
  ..setEndpoint('http://api.example.com'); // Not secure!
```

**3. Request Validation**
```dart
// Good: Validate API responses
final response = await http.get(Uri.parse(url));
if (response.statusCode != 200) {
  throw ApiException('Request failed with status: ${response.statusCode}');
}

// Bad: Ignore response status
final response = await http.get(Uri.parse(url));
// Use response even if failed
```

---

## F4C0 Performance Guidelines

### F469 Widget Performance

**1. Avoid Unnecessary Rebuilds**
```dart
// Good: Use const constructors
const MyWidget() : super();

// Bad: Non-const constructors
MyWidget() : super();
```

**2. Use Keys Properly**
```dart
// Good: Use keys for lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ListItem(
      key: ValueKey(items[index].id), // Unique key
      item: items[index],
    );
  },
)

// Bad: No keys or index as key
ListView.builder(
  itemBuilder: (context, index) {
    return ListItem(
      key: Key('$index'), // Avoid index as key
    );
  },
)
```

**3. Optimize ListView**
```dart
// Good: Use ListView.builder for large lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(item: items[index]),
)

// Bad: Use Column for large lists
Column(
  children: items.map((item) => ItemWidget(item: item)).toList(),
) // Renders all items at once!
```

### F469 State Management Performance

**1. Avoid Unnecessary Watches**
```dart
// Good: Watch only what you need
final user = ref.watch(userProvider);

// Bad: Watch many providers in one Consumer
Consumer(
  builder: (context, ref, child) {
    final user = ref.watch(userProvider);
    final bookings = ref.watch(bookingsProvider);
    final rooms = ref.watch(roomsProvider);
    final settings = ref.watch(settingsProvider);
    // Too many watches!
  },
)
```

**2. Use Select for Partial Updates**
```dart
// Good: Use select for partial state
final userName = ref.watch(userProvider.select((user) => user.name));

// Bad: Watch entire state when only part is needed
final user = ref.watch(userProvider);
final name = user.name; // Unnecessary rebuilds when other fields change
```

**3. Avoid Heavy Computations in Build**
```dart
// Good: Move heavy computations to initState or providers
@override
void initState() {
  super.initState();
  _expensiveComputation();
}

// Bad: Heavy computations in build
@override
Widget build(BuildContext context) {
  final result = _expensiveComputation(); // Runs on every rebuild!
  return Text('$result');
}
```

### F469 Database Performance

**1. Optimize Queries**
```dart
// Good: Select only needed columns
final query = select(rooms, distinct: true)
  ..where((t) => t.isAvailable.equals(true))
  ..limit(10);

// Bad: Select all columns
final query = select(rooms)..get(); // Fetches all data!
```

**2. Use Indexes**
```dart
// Good: Create indexes for frequently queried columns
@override
List<Index> get indexes => [
  Index.on([roomType, isAvailable]),
];

// Bad: No indexes on queried columns
// Queries will be slow!
```

**3. Batch Operations**
```dart
// Good: Use batch operations
await db.batch((batch) {
  batch.insert(rooms, room1);
  batch.insert(rooms, room2);
  batch.insert(rooms, room3);
});

// Bad: Individual operations
await db.into(rooms).insert(room1);
await db.into(rooms).insert(room2);
await db.into(rooms).insert(room3);
```

---

## F4C1 Testing Guidelines

### F469 Unit Testing

**1. Test Structure**
```dart
// Good: Follow AAA pattern (Arrange, Act, Assert)
group('BookingService', () {
  late BookingService service;
  late MockBookingRepository mockRepo;
  
  setUp(() {
    mockRepo = MockBookingRepository();
    service = BookingService(mockRepo);
  });
  
  test('createBooking should return booking on success', () async {
    // Arrange
    when(mockRepo.createBooking(any)).thenAnswer((_) async => booking);
    
    // Act
    final result = await service.createBooking(booking);
    
    // Assert
    expect(result, booking);
    verify(mockRepo.createBooking(booking)).called(1);
  });
});

// Bad: No structure, unclear tests
test('test booking', () async {
  // Everything in one test
})
```

**2. Mock Usage**
```dart
// Good: Use Mockito for mocking
when(mockRepo.getBookings()).thenAnswer((_) async => [booking1, booking2]);

// Bad: Real implementations in tests
final realRepo = BookingRepository(client); // Avoid!
```

**3. Test Coverage**
- **Aim for 80%+ coverage**
- **Test happy paths**
- **Test error cases**
- **Test edge cases**

### F469 Widget Testing

**1. Test Widget Rendering**
```dart
// Good: Test widget appearance
testWidgets('BookingButton renders correctly', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookingButton(onPressed: () {}),
    ),
  );
  
  expect(find.text('Book Now'), findsOneWidget);
  expect(find.byType(ElevatedButton), findsOneWidget);
});

// Bad: No assertions
 testWidgets('test', (tester) async {
   await tester.pumpWidget(BookingButton());
 });
```

**2. Test User Interactions**
```dart
// Good: Test button presses
testWidgets('BookingButton calls onPressed', (tester) async {
  bool pressed = false;
  
  await tester.pumpWidget(
    MaterialApp(
      home: BookingButton(onPressed: () => pressed = true),
    ),
  );
  
  await tester.tap(find.text('Book Now'));
  await tester.pump();
  
  expect(pressed, true);
});
```

### F469 Integration Testing

**1. Test User Journeys**
```dart
// Good: Test complete flows
testWidgets('Login to booking flow', (tester) async {
  // Login
  await tester.pumpWidget(App());
  await tester.enterText(find.byKey(loginEmailKey), 'user@example.com');
  await tester.enterText(find.byKey(loginPasswordKey), 'password');
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
  
  // Verify login success
  expect(find.text('Welcome'), findsOneWidget);
  
  // Navigate to booking
  await tester.tap(find.text('Book a Room'));
  await tester.pumpAndSettle();
  
  // Verify booking screen
  expect(find.text('Available Rooms'), findsOneWidget);
});
```

---

## F4C2 Localization (RTL) Guidelines

### F469 RTL Support

**1. Text Direction**
```dart
// Good: Use TextDirection.rtl for Arabic
Text(
  'مرحبا',
  textDirection: TextDirection.rtl,
)

// Bad: Hardcoded LTR for Arabic
Text(
  'مرحبا',
  textDirection: TextDirection.ltr, // Wrong for Arabic!
)
```

**2. Layout Direction**
```dart
// Good: Use Directionality widget
Directionality(
  textDirection: TextDirection.rtl,
  child: MyWidget(),
)

// Bad: Assume LTR
MyWidget() // May not work correctly for RTL
```

**3. Localization**
```dart
// Good: Use Flutter localization
MaterialApp(
  localizationsDelegates: [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: [
    Locale('en'),
    Locale('ar'),
  ],
  locale: Locale('ar'), // Default to Arabic
)

// Bad: Hardcoded strings
Text('Hello') // Not localized!
```

**4. String Localization**
```dart
// Good: Use localized strings
Text(AppLocalizations.of(context)!.welcomeMessage)

// Bad: Hardcoded strings
Text('Welcome') // Not localized!
```

**5. RTL-Aware Widgets**
```dart
// Good: Use RTL-aware widgets
Row(
  textDirection: TextDirection.rtl,
  children: [
    Icon(Icons.arrow_back), // Will point right in RTL
    Text('الرجوع'),
  ],
)

// Bad: Assume LTR
Row(
  children: [
    Icon(Icons.arrow_back), // Will point left in RTL (wrong!)
    Text('Back'),
  ],
)
```

---

## F4C4 Summary

This document provides **comprehensive instructions** for GitHub Copilot when reviewing code in the **Marina Hotel Mobile** project. By following these guidelines, Copilot can provide **more accurate and relevant feedback** tailored to our project's specific needs.

**Key Takeaways:**
1. **Follow project conventions** (naming, structure, patterns)
2. **Focus on security and data integrity** (high priority)
3. **Optimize for performance** (widgets, state, database)
4. **Ensure RTL support** (Arabic localization)
5. **Write maintainable code** (clean architecture, testing)

---

## F4C4 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-03 | Initial Copilot instructions |

---

> **F44D Note:** This document should be updated as the project evolves and new conventions are established.

---

**F44B Happy Coding with Copilot! F389**
