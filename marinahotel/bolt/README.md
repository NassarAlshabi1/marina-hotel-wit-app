# Marina Hotel Bolt backend integration

This module provides backend endpoints for the Bolt UI reusing the shared backend under `marinahotel/includes`.

Shared includes used
- `includes/db.php` for DB connection
- `includes/auth_check.php` for auth and session
- `includes/functions.php` for utilities such as `send_yemeni_whatsapp()`

Auth and permissions
- All routes require a logged-in session via `auth_check.php`.
- Payment actions require any of: `manage_payments` or `finance_manage`.
- Checkout actions require any of: `manage_bookings`, `bookings_edit`, or `rooms_manage`.
- Booking preparation requires any of: `manage_bookings` or `bookings_add`.

Endpoints
- `bolt/api/payments.php`
  - GET ?booking_id=ID → returns booking details and payment calculations identical to admin.
  - POST action=add_payment, booking_id, amount, payment_date, payment_method, notes → inserts into `payment`, sends WhatsApp message using the same format as admin.
  - POST action=checkout, booking_id → sets booking/room status to "شاغرة" only when remaining == 0.

- `bolt/api/guests.php`
  - GET [search=term] → returns guest aggregates (distinct fields, total_bookings, active_bookings, last_visit). Default limit 50 when search empty.

- `bolt/api/guest_history.php`
  - GET ?name=Guest → returns guest booking history and stats.

- `bolt/api/prepare_booking.php`
  - POST guest fields → returns a prefill payload for creating a new booking.

Database
- Assumes the canonical schema (tables: bookings, rooms, payment, cash_register, cash_transactions, booking_notes, users, permissions, user_permissions) as in `hotel_db-(12).sql` / `marinahotel/database.sql`.

Notes
- No cash register/transactions side effects are added here to keep parity with the admin payment flow.
- These endpoints return JSON; keep Bolt UI unchanged and call these endpoints from it.
