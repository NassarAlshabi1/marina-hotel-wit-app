# Flutter to Kotlin Screen Mapping

| Flutter Screen | Kotlin Activity/Fragment + Layout | Widget Translation Summary | Notes |
| --- | --- | --- | --- |
| `dashboard_screen.dart` | `DashboardActivity` + `activity_dashboard.xml`, `view_stat_card.xml`, `view_recent_activity.xml`, `view_quick_action.xml` | Flutter `SingleChildScrollView`, `GridView.count`, cards, and quick-action buttons mapped to `NestedScrollView`, `GridLayout`, `MaterialCardView`, and custom inflated view templates. | Stats now come from Room via DashboardViewModel; sync button remains stubbed. |
| `bookings/bookings_list.dart` | `BookingsListActivity` + `activity_bookings_list.xml`, `item_booking.xml` | `AppScaffold`, search dialog, chips, list, and FAB mirrored via `MaterialToolbar`, `TextInputLayout`, `ChipGroup`, `RecyclerView`, and `FloatingActionButton`. | Powered by Room via BookingsViewModel (Flow); ListAdapter + DiffUtil used. |
| `bookings/booking_edit.dart` | `BookingEditActivity` + `activity_booking_edit.xml` | Flutter `Form`, `TextFormField`, dropdowns, and date pickers mapped to `TextInputLayout`/`TextInputEditText`, `AutoCompleteTextView`, and `DatePickerDialog`. | Persists to Room; validation added for dates and required fields. |
| `employees/employees_list.dart` | `EmployeesListActivity` + `activity_employees_list.xml`, `item_employee.xml`, `dialog_employee_form.xml` | `StreamBuilder`-driven list reproduced with `RecyclerView`; dialogs mirror Flutter forms via `AlertDialog` + view binding. | Live data from Room via EmployeesViewModel; input validation added. |
| `expenses/expenses_list.dart` | `ExpensesListActivity` + `activity_expenses_list.xml`, `item_expense.xml`, `dialog_expense_form.xml` | Flutter list and dialog inputs translated to Material text fields and recycler adapter. | Backed by Room via ExpensesViewModel; validation/errors surfaced. |
| `finance/finance_screen.dart` | `FinanceActivity` + `activity_finance.xml` | Flutter wrapper embedding `PaymentsMainScreen` mapped to dedicated activity hosting the same tabbed fragments as payments module. | Shares fragments with payments section; ensures finance entry point exists. |
| `finance/payments_list.dart` | `PaymentsListActivity` + `activity_payments_list.xml`, `item_payment.xml` | Flutter `AppScaffold` with list translated to Activity + `RecyclerView` reusing payment item layout. | Streams replaced with static items. |
| `notes/notes_screen.dart` | `NotesActivity`, `NotesListFragment`, `NotesAdapter` + `activity_notes.xml`, `fragment_notes_list.xml`, `item_note.xml` | Flutter `TabBar`/`TabBarView`, filters, and cards mirrored with `TabLayout`, `ViewPager2`, and `MaterialCardView`. | Notes wiring prepared with NotesViewModel for booking-scoped notes. |
| `payments/payments_main_screen.dart` | `PaymentsMainActivity` + `activity_payments_main.xml` with `PaymentsOverviewFragment`, `PaymentsTransactionsFragment`, `PaymentsBookingsFragment` + related layouts | Flutter tabs, charts, and lists mapped to `TabLayout`/`ViewPager2`, `LinearProgressIndicator`, and recycler adapters. | Overview/transactions now read from Room via PaymentsViewModel; bookings tab pending balances can be extended similarly. |
| `payments/payment_history_screen.dart` | `PaymentHistoryActivity` + `activity_payment_history.xml`, `item_payment_transaction.xml` | Flutter filter chips and transaction list replicated using `ChipGroup` and `RecyclerView`. | Advanced filtering logic simplified to client-side filtering on sample data. |
| `payments/booking_payment_screen.dart` | `BookingPaymentActivity` + `activity_booking_payment.xml`, `view_payment_method.xml`, transaction item layout | Flutter tabbed payment flow condensed into single screen with grid of methods, list of transactions, and action buttons. | Multi-tab actions merged; new payment dialog uses basic inputs. |
| `payments/booking_checkout_screen.dart` | `BookingCheckoutActivity` + `activity_booking_checkout.xml`, `item_charge.xml` | Checkout summary cards and payment actions mapped to Material cards and recycler. | Room/booking repositories replaced with static data; payment button routes to booking payment screen. |
| `payments/payments_list.dart` | Covered above via `PaymentsListActivity`. | Same as finance list entry. | — |
| `reports/reports_screen.dart` | `ReportsActivity` + `activity_reports.xml` | Flutter `BarChart` widgets approximated using `MaterialCardView` + horizontal `ProgressBar`. | Chart analytics require manual MPAndroidChart integration if needed. |
| `rooms/rooms_main.dart` | `RoomsMainActivity` + `activity_rooms_main.xml` | Flutter tab host translated to `TabLayout` + `ViewPager2`. | Additional sync icon handled via toast action. |
| `rooms/rooms_dashboard.dart` | `RoomsDashboardFragment` + `fragment_rooms_dashboard.xml`, `item_room.xml`, `RoomDetailsDialog` | Grid of rooms represented by `RecyclerView` grid and `MaterialCardView`; room dialog mimics Flutter alert. | Floor grouping simplified to single sample floor; extend adapter for multi-floor data. |
| `rooms/rooms_list.dart` | `RoomsListFragment` + `fragment_rooms_list.xml`, `item_room.xml` | Searchable list re-created with `TextInputLayout` search and `RecyclerView`. | Image picker omitted; add hooking required for real data. |
| `settings/settings_screen.dart` | `SettingsMainActivity` + `activity_settings_main.xml`, `view_settings_item.xml` | Flutter grid menu reproduced through dynamic `GridLayout` inflating Material cards. | Drawer navigation replaced by explicit intents per card. |
| `settings/settings_employees.dart` | `SettingsEmployeesActivity` + `activity_settings_employees.xml`, shared employee item/dialog layouts | Flutter stats, dialogs, and salary actions mapped to Material cards and dialogs. | Salary withdrawal + history simplified to toast feedback. |
| `settings/settings_guests.dart` | `SettingsGuestsActivity` + `activity_settings_guests.xml`, `item_guest.xml` | Guest search list mirrored using Material text field + recycler. | History dialogs reduced to inline text; extend for detail dialogs if required. |
| `settings/settings_maintenance.dart` | `SettingsMaintenanceActivity` + `activity_settings_maintenance.xml` | Maintenance actions rendered as tappable Material cards. | Progress dialogs replaced by toast notifications; integrate async ops as needed. |
| `settings/settings_users.dart` | `SettingsUsersActivity` + `activity_settings_users.xml`, `dialog_user_form.xml` | User info cards, switches, and dialogs mirrored with Material components. | Role selection uses dropdown with static roles; password dialog repurposes same layout. |

## Shared Components

- Drawer experience from Flutter `AppScaffold` implemented in `MainActivity` + `ActivityMainBinding` using `DrawerLayout`, `NavigationView`, and quick-action cards.
- Reusable view templates (`view_stat_card.xml`, `view_payment_method.xml`, etc.) emulate common Flutter widgets like cards, chips, and grid tiles.
- Recycler adapters correspond to Flutter `ListView.builder`/`GridView.builder` usages across bookings, rooms, payments, employees, expenses, notes, and guests.

## Manual Adjustment Notes

- Data providers (Riverpod streams, repositories) are represented with sample data placeholders; connect to actual data sources for production use.
- Chart visualizations (`fl_chart`) are approximated with progress indicators; integrate MPAndroidChart or another charting library for full parity.
- Image picking and file exports referenced in Flutter are stubbed; add platform integrations where required.
- Dialog-based workflows mirror UI structure but omit business logic (validation, persistence, printing); implement backend wiring as needed.
