<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// تحديد التاريخ الحالي
$today = date('Y-m-d');

// التحقق مما إذا كان هناك سجل صندوق مفتوح لليوم الحالي
$check_query = "SELECT * FROM cash_register WHERE date = ? AND status = 'open'";
$stmt = $conn->prepare($check_query);
$stmt->bind_param("s", $today);
$stmt->execute();
$result = $stmt->get_result();

// إذا لم يكن هناك سجل مفتوح، قم بإنشاء واحد جديد
if ($result->num_rows == 0) {
    // الحصول على الرصيد الختامي لآخر يوم
    $last_closing_query = "SELECT closing_balance FROM cash_register WHERE status = 'closed' ORDER BY date DESC LIMIT 1";
    $last_closing_result = $conn->query($last_closing_query);
    $opening_balance = 0;
    
    if ($last_closing_result && $last_closing_result->num_rows > 0) {
        $last_closing = $last_closing_result->fetch_assoc();
        $opening_balance = $last_closing['closing_balance'];
    }
    
    // إنشاء سجل جديد للصندوق
    $create_query = "INSERT INTO cash_register (date, opening_balance, status) VALUES (?, ?, 'open')";
    $create_stmt = $conn->prepare($create_query);
    $create_stmt->bind_param("sd", $today, $opening_balance);
    $create_stmt->execute();
    
    // إعادة تحميل البيانات
    $stmt->execute();
    $result = $stmt->get_result();
}

$register = $result->fetch_assoc();
$register_id = $register['id'];

// معالجة إضافة حركة نقدية جديدة
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if ($_POST['action'] === 'add_transaction') {
        $transaction_type = $_POST['transaction_type'];
        $amount = $_POST['amount'];
        $reference_type = $_POST['reference_type'];
        $reference_id = $_POST['reference_id'] ?? 0;
        $description = $_POST['description'];
        $transaction_time = date('Y-m-d H:i:s');
        
        // إضافة الحركة النقدية
        $add_transaction_query = "INSERT INTO cash_transactions 
                                 (register_id, transaction_type, amount, reference_type, reference_id, description, transaction_time) 
                                 VALUES (?, ?, ?, ?, ?, ?, ?)";
        $add_stmt = $conn->prepare($add_transaction_query);
        $add_stmt->bind_param("isdsiss", $register_id, $transaction_type, $amount, $reference_type, $reference_id, $description, $transaction_time);
        
        if ($add_stmt->execute()) {
            // تحديث إجمالي الإيرادات أو المصروفات في سجل الصندوق
            if ($transaction_type === 'income') {
                $update_query = "UPDATE cash_register SET total_income = total_income + ? WHERE id = ?";
            } else {
                $update_query = "UPDATE cash_register SET total_expense = total_expense + ? WHERE id = ?";
            }
            
            $update_stmt = $conn->prepare($update_query);
            $update_stmt->bind_param("di", $amount, $register_id);
            $update_stmt->execute();
            
            header("Location: cash_register.php?success=تمت إضافة الحركة النقدية بنجاح");
            exit;
        } else {
            $error_message = "حدث خطأ أثناء إضافة الحركة النقدية: " . $conn->error;
        }
    } elseif ($_POST['action'] === 'close_register') {
        $closing_balance = $_POST['closing_balance'];
        $notes = $_POST['notes'];
        
        // إغلاق سجل الصندوق
        $close_query = "UPDATE cash_register SET closing_balance = ?, notes = ?, status = 'closed' WHERE id = ?";
        $close_stmt = $conn->prepare($close_query);
        $close_stmt->bind_param("dsi", $closing_balance, $notes, $register_id);
        
        if ($close_stmt->execute()) {
            header("Location: cash_register.php?success=تم إغلاق سجل الصندوق بنجاح");
            exit;
        } else {
            $error_message = "حدث خطأ أثناء إغلاق سجل الصندوق: " . $conn->error;
        }
    }
}

// جلب حركات الصندوق لليوم الحالي
$transactions_query = "SELECT * FROM cash_transactions WHERE register_id = ? ORDER BY transaction_time DESC";
$transactions_stmt = $conn->prepare($transactions_query);
$transactions_stmt->bind_param("i", $register_id);
$transactions_stmt->execute();
$transactions_result = $transactions_stmt->get_result();

// حساب الرصيد الحالي
$current_balance = $register['opening_balance'] + $register['total_income'] - $register['total_expense'];
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>سجل الصندوق - فندق مارينا بلازا</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        .card-header {
            border-radius: 15px 15px 0 0 !important;
            font-weight: bold;
        }
        .form-label {
            font-weight: bold;
        }
        .transaction-card {
            border-right: 5px solid;
            margin-bottom: 10px;
        }
        .transaction-income {
            border-right-color: #28a745;
        }
        .transaction-expense {
            border-right-color: #dc3545;
        }
        .balance-card {
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 20px;
        }
        .balance-title {
            font-size: 1rem;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .balance-amount {
            font-size: 1.5rem;
            font-weight: bold;
        }
        .balance-opening {
            color: #6c757d;
        }
        .balance-current {
            color: #0d6efd;
        }
        .balance-income {
            color: #28a745;
        }
        .balance-expense {
            color: #dc3545;
        }
        .transaction-time {
            font-size: 0.8rem;
            color: #6c757d;
        }
        .transaction-amount {
            font-weight: bold;
        }
        .transaction-amount.income {
            color: #28a745;
        }
        .transaction-amount.expense {
            color: #dc3545;
        }
        .transaction-description {
            margin-top: 5px;
        }
        .register-status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.8rem;
        }
        .register-status.open {
            background-color: #d1e7dd;
            color: #0f5132;
        }
        .register-status.closed {
            background-color: #f8d7da;
            color: #842029;
        }
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            .balance-amount {
                font-size: 1.2rem;
            }
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <div class="d-flex justify-content-between mb-3">
            <a href="../dashboard.php" class="btn btn-outline-primary fw-bold">
                ← العودة إلى لوحة التحكم
            </a>
            <a href="cash_reports.php" class="btn btn-info fw-bold">
                <i class="fas fa-chart-bar me-1"></i> تقارير الصندوق
            </a>
        </div>

        <h2 class="text-center mb-4 text-primary fw-bold">سجل الصندوق - فندق مارينا بلازا</h2>
        
        <?php if (isset($_GET['success'])): ?>
            <div class="alert alert-success text-center" role="alert">
                <?= htmlspecialchars($_GET['success']); ?>
            </div>
        <?php endif; ?>
        
        <?php if (isset($error_message)): ?>
            <div class="alert alert-danger text-center" role="alert">
                <?= htmlspecialchars($error_message); ?>
            </div>
        <?php endif; ?>

        <div class="row mb-4">
            <div class="col-md-12">
                <div class="card">
                    <div class="card-header bg-primary text-white d-flex justify-content-between align-items-center">
                        <h4 class="mb-0">سجل الصندوق ليوم: <?= date('Y-m-d', strtotime($register['date'])); ?></h4>
                        <span class="register-status <?= $register['status']; ?>">
                            <?= $register['status'] === 'open' ? 'مفتوح' : 'مغلق'; ?>
                        </span>
                    </div>
                    <div class="card-body">
                        <div class="row">
                            <div class="col-md-3">
                                <div class="balance-card">
                                    <div class="balance-title">الرصيد الافتتاحي</div>
                                    <div class="balance-amount balance-opening"><?= number_format($register['opening_balance'], 2); ?> د.إ</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="balance-card">
                                    <div class="balance-title">إجمالي الإيرادات</div>
                                    <div class="balance-amount balance-income">+ <?= number_format($register['total_income'], 2); ?> د.إ</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="balance-card">
                                    <div class="balance-title">إجمالي المصروفات</div>
                                    <div class="balance-amount balance-expense">- <?= number_format($register['total_expense'], 2); ?> د.إ</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="balance-card">
                                    <div class="balance-title">الرصيد الحالي</div>
                                    <div class="balance-amount balance-current"><?= number_format($current_balance, 2); ?> د.إ</div>
                                </div>
                            </div>
                        </div>

                        <?php if ($register['status'] === 'open'): ?>
                            <div class="row mt-4">
                                <div class="col-md-6">
                                    <div class="card">
                                        <div class="card-header bg-success text-white">
                                            <h5 class="mb-0">إضافة حركة نقدية جديدة</h5>
                                        </div>
                                        <div class="card-body">
                                            <form method="POST" action="">
                                                <input type="hidden" name="action" value="add_transaction">
                                                
                                                <div class="mb-3">
                                                    <label for="transaction_type" class="form-label">نوع الحركة</label>
                                                    <select class="form-select" id="transaction_type" name="transaction_type" required>
                                                        <option value="income">إيراد</option>
                                                        <option value="expense">مصروف</option>
                                                    </select>
                                                </div>
                                                
                                                <div class="mb-3">
                                                    <label for="amount" class="form-label">المبلغ</label>
                                                    <input type="number" step="0.01" class="form-control" id="amount" name="amount" required>
                                                </div>
                                                
                                                <div class="mb-3">
                                                    <label for="reference_type" class="form-label">نوع المرجع</label>
                                                    <select class="form-select" id="reference_type" name="reference_type" required>
                                                        <option value="booking">حجز</option>
                                                        <option value="restaurant">مطعم</option>
                                                        <option value="service">خدمة إضافية</option>
                                                        <option value="salary">راتب</option>
                                                        <option value="utility">فاتورة</option>
                                                        <option value="purchase">مشتريات</option>
                                                        <option value="other">أخرى</option>
                                                    </select>
                                                </div>
                                                
                                                <div class="mb-3">
                                                    <label for="reference_id" class="form-label">رقم المرجع (اختياري)</label>
                                                    <input type="number" class="form-control" id="reference_id" name="reference_id">
                                                </div>
                                                
                                                <div class="mb-3">
                                                    <label for="description" class="form-label">الوصف</label>
                                                    <textarea class="form-control" id="description" name="description" rows="3" required></textarea>
                                                </div>
                                                
                                                <div class="d-grid">
                                                    <button type="submit" class="btn btn-success fw-bold">
                                                        <i class="fas fa-plus-circle me-1"></i> إضافة الحركة
                                                    </button>
                                                </div>
                                            </form>
                                        </div>
                                    </div>
                                </div>
                                
                                <div class="col-md-6">
                                    <div class="card">
                                        <div class="card-header bg-danger text-white">
                                            <h5 class="mb-0">إغلاق الصندوق</h5>
                                        </div>
                                        <div class="card-body">
                                            <form method="POST" action="" onsubmit="return confirm('هل أنت متأكد من إغلاق الصندوق؟');">
                                                <input type="hidden" name="action" value="close_register">
                                                
                                                <div class="mb-3">
                                                    <label for="closing_balance" class="form-label">الرصيد الختامي</label>
                                                    <input type="number" step="0.01" class="form-control" id="closing_balance" name="closing_balance" value="<?= $current_balance; ?>" required>
                                                </div>
                                                
                                                <div class="mb-3">
                                                    <label for="notes" class="form-label">ملاحظات</label>
                                                    <textarea class="form-control" id="notes" name="notes" rows="3"></textarea>
                                                </div>
                                                
                                                <div class="d-grid">
                                                    <button type="submit" class="btn btn-danger fw-bold">
                                                        <i class="fas fa-lock me-1"></i> إغلاق الصندوق
                                                    </button>
                                                </div>
                                            </form>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        <?php endif; ?>

                        <div class="mt-4">
                            <h5 class="mb-3">حركات الصندوق</h5>
                            
                            <?php if ($transactions_result->num_rows > 0): ?>
                                <?php while ($transaction = $transactions_result->fetch_assoc()): ?>
                                    <div class="transaction-card <?= $transaction['transaction_type'] === 'income' ? 'transaction-income' : 'transaction-expense'; ?> p-3">
                                        <div class="d-flex justify-content-between">
                                            <div>
                                                <div class="transaction-time">
                                                    <i class="fas fa-clock me-1"></i> <?= date('H:i:s', strtotime($transaction['transaction_time'])); ?>
                                                </div>
                                                <div class="transaction-description">
                                                    <?= htmlspecialchars($transaction['description']); ?>
                                                </div>
                                                <div class="small text-muted">
                                                    <?php
                                                    $reference_types = [
                                                        'booking' => 'حجز',
                                                        'restaurant' => 'مطعم',
                                                        'service' => 'خدمة إضافية',
                                                        'salary' => 'راتب',
                                                        'utility' => 'فاتورة',
                                                        'purchase' => 'مشتريات',
                                                        'other' => 'أخرى'
                                                    ];
                                                    echo $reference_types[$transaction['reference_type']] ?? $transaction['reference_type'];
                                                    if ($transaction['reference_id']) {
                                                        echo ' #' . $transaction['reference_id'];
                                                    }
                                                    ?>
                                                </div>
                                            </div>
                                            <div class="transaction-amount <?= $transaction['transaction_type']; ?>">
                                                <?= $transaction['transaction_type'] === 'income' ? '+' : '-'; ?> <?= number_format($transaction['amount'], 2); ?> د.إ
                                            </div>
                                        </div>
                                    </div>
                                <?php endwhile; ?>
                            <?php else: ?>
                                <div class="alert alert-info text-center">
                                    لا توجد حركات نقدية مسجلة لهذا اليوم
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

<?php
$stmt->close();
$transactions_stmt->close();
if (isset($add_stmt)) $add_stmt->close();
if (isset($update_stmt)) $update_stmt->close();
if (isset($close_stmt)) $close_stmt->close();
$conn->close();
?>
