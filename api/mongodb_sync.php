<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE');
header('Access-Control-Allow-Headers: Content-Type');

require_once '../includes/db.php';

class MongoDBSync {
    private $mongoClient;
    private $database;
    private $guestsCollection;
    private $bookingsCollection;
    
    private $mongoUri = "mongodb+srv://Nassar:<password>@cluster0.ai2ybe7.mongodb.net/?appName=Cluster0";
    private $databaseName = "marina_hotel";
    
    public function __construct($password) {
        try {
            require_once 'vendor/autoload.php';
            
            $uri = str_replace('<password>', $password, $this->mongoUri);
            
            $this->mongoClient = new MongoDB\Client($uri);
            $this->database = $this->mongoClient->selectDatabase($this->databaseName);
            $this->guestsCollection = $this->database->selectCollection('guests');
            $this->bookingsCollection = $this->database->selectCollection('bookings');
            
            error_log("✅ Connected to MongoDB successfully");
        } catch (Exception $e) {
            error_log("❌ MongoDB connection failed: " . $e->getMessage());
            throw new Exception("Failed to connect to MongoDB: " . $e->getMessage());
        }
    }
    
    public function syncGuestsFromMySQL($conn) {
        try {
            $query = "SELECT g.*, 
                      COUNT(b.booking_id) as total_bookings,
                      MAX(b.updated_at) as last_booking_date
                      FROM guests g
                      LEFT JOIN bookings b ON g.guest_id = b.guest_id
                      GROUP BY g.guest_id
                      ORDER BY g.updated_at DESC";
            
            $result = $conn->query($query);
            
            if (!$result) {
                throw new Exception("Database query failed: " . $conn->error);
            }
            
            $syncedCount = 0;
            $deviceId = 'hotel_server_php';
            
            while ($row = $result->fetch_assoc()) {
                $guestData = [
                    'guest_id' => (string)$row['guest_id'],
                    'full_name' => $row['full_name'],
                    'phone' => $row['phone'],
                    'email' => $row['email'],
                    'id_number' => $row['id_number'],
                    'nationality' => $row['nationality'],
                    'total_bookings' => (int)$row['total_bookings'],
                    'last_booking_date' => $row['last_booking_date'],
                    'created_at' => $row['created_at'],
                    'updated_at' => date('c'),
                    'device_id' => $deviceId,
                    'synced_from' => 'mysql',
                ];
                
                $this->guestsCollection->updateOne(
                    ['guest_id' => (string)$row['guest_id']],
                    ['$set' => $guestData],
                    ['upsert' => true]
                );
                
                $syncedCount++;
            }
            
            return [
                'success' => true,
                'synced_count' => $syncedCount,
                'message' => "تم مزامنة $syncedCount نزيل بنجاح"
            ];
            
        } catch (Exception $e) {
            error_log("❌ Sync failed: " . $e->getMessage());
            return [
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
    
    public function syncBookingsFromMySQL($conn) {
        try {
            $query = "SELECT b.*, 
                      g.full_name as guest_name,
                      r.room_number,
                      COALESCE(SUM(ct.amount), 0) as paid_amount
                      FROM bookings b
                      JOIN guests g ON b.guest_id = g.guest_id
                      JOIN rooms r ON b.room_id = r.room_id
                      LEFT JOIN cash_transactions ct ON ct.reference_id = b.booking_id 
                          AND ct.transaction_type = 'income'
                      WHERE b.updated_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                      GROUP BY b.booking_id
                      ORDER BY b.updated_at DESC";
            
            $result = $conn->query($query);
            
            if (!$result) {
                throw new Exception("Database query failed: " . $conn->error);
            }
            
            $syncedCount = 0;
            $deviceId = 'hotel_server_php';
            
            while ($row = $result->fetch_assoc()) {
                $bookingData = [
                    'booking_id' => (string)$row['booking_id'],
                    'guest_name' => $row['guest_name'],
                    'room_number' => $row['room_number'],
                    'status' => $row['status'],
                    'check_in_date' => $row['check_in_date'],
                    'check_out_date' => $row['check_out_date'],
                    'total_amount' => (float)$row['total_amount'],
                    'paid_amount' => (float)$row['paid_amount'],
                    'created_at' => $row['created_at'],
                    'updated_at' => date('c'),
                    'device_id' => $deviceId,
                    'synced_from' => 'mysql',
                ];
                
                $this->bookingsCollection->updateOne(
                    ['booking_id' => (string)$row['booking_id']],
                    ['$set' => $bookingData],
                    ['upsert' => true]
                );
                
                $syncedCount++;
            }
            
            return [
                'success' => true,
                'synced_count' => $syncedCount,
                'message' => "تم مزامنة $syncedCount حجز بنجاح"
            ];
            
        } catch (Exception $e) {
            error_log("❌ Sync failed: " . $e->getMessage());
            return [
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
    
    public function getStats() {
        try {
            $guestsCount = $this->guestsCollection->countDocuments();
            $bookingsCount = $this->bookingsCollection->countDocuments();
            
            return [
                'success' => true,
                'stats' => [
                    'total_guests' => $guestsCount,
                    'total_bookings' => $bookingsCount,
                    'last_sync' => date('Y-m-d H:i:s'),
                ]
            ];
        } catch (Exception $e) {
            return [
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
}

$action = $_GET['action'] ?? '';
$password = $_GET['password'] ?? $_POST['password'] ?? '';

if (empty($password)) {
    echo json_encode([
        'success' => false,
        'error' => 'كلمة مرور MongoDB مطلوبة'
    ]);
    exit;
}

try {
    $mongoSync = new MongoDBSync($password);
    
    switch ($action) {
        case 'sync_guests':
            $result = $mongoSync->syncGuestsFromMySQL($conn);
            echo json_encode($result);
            break;
            
        case 'sync_bookings':
            $result = $mongoSync->syncBookingsFromMySQL($conn);
            echo json_encode($result);
            break;
            
        case 'sync_all':
            $guestsResult = $mongoSync->syncGuestsFromMySQL($conn);
            $bookingsResult = $mongoSync->syncBookingsFromMySQL($conn);
            
            echo json_encode([
                'success' => true,
                'guests' => $guestsResult,
                'bookings' => $bookingsResult,
            ]);
            break;
            
        case 'stats':
            $result = $mongoSync->getStats();
            echo json_encode($result);
            break;
            
        default:
            echo json_encode([
                'success' => false,
                'error' => 'إجراء غير صحيح. استخدم: sync_guests, sync_bookings, sync_all, أو stats'
            ]);
    }
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
?>
