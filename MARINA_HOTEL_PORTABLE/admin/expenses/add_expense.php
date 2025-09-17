<?php
session_start();
require_once '../../includes/config.php';
require_once '../../includes/db.php';

// التحقق من تسجيل الدخول فقط
if (!isset($_SESSION['user_id'])) {
    header('Location: ../../login.php');
    exit();
}

// جلب البيانات اللازمة للقوائم المنسدلة
$employees = [];
$suppliers = [];

// جلب الموظفين النشطين
$emp_query = "SELECT id, name FROM employees WHERE status = 'active'";
$emp_result = $conn->query($emp_query);
if ($emp_result === false) {
    die("خطأ في جلب بيانات الموظفين: " . $conn->error);
}
while ($row = $emp_result->fetch_assoc()) {
    $employees[$row['id']] = $row['name'];
}

// جلب الموردين
$sup_query = "SELECT id, name FROM suppliers";
$sup_result = $conn->query($sup_query);
if ($sup_result === false) {
    die("خطأ في جلب بيانات الموردين: " . $conn->error);
}
while ($row = $sup_result->fetch_assoc()) {
    $suppliers[$row['id']] = $row['name'];
}

// معالجة POST request
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $expense_type = $_POST['expense_type'];
    $description = trim(htmlspecialchars($_POST['description']));
    $amount = floatval($_POST['amount']);
    $date = $_POST['date'];
    $related_id = isset($_POST['related_id']) ? (int)$_POST['related_id'] : null;
    $withdrawal_type = isset($_POST['withdrawal_type']) ? $_POST['withdrawal_type'] : null;

    // التحقق من الصحة
    $errors = [];

    // تحقق أساسي
    if (empty($expense_type)) {
        $errors[] = 'يجب تحديد نوع المصروف';
    }

    if ($amount <= 0) {
        $errors[] = 'يجب أن يكون المبلغ أكبر من الصفر';
    }

    // تحقق حسب النوع
    switch ($expense_type) {
        case 'salaries':
            if (empty($related_id)) {
                $errors[] = 'يجب تحديد الموظف';
            }
            break;

        case 'utilities':
            if (empty($description)) {
                $errors[] = 'يجب إدخال وصف الفاتورة';
            }
            break;

        case 'purchases':
            if (empty($related_id)) {
                $errors[] = 'يجب تحديد المورد';
            }
            break;

        default:
            if (empty($description)) {
                $errors[] = 'يجب إدخال وصف المصروف';
            }
    }

    // إذا لم يكن هناك أخطاء
    if (empty($errors)) {
        try {
            $conn->begin_transaction();

            if ($expense_type === 'salaries') {
                // التحقق من وجود جدول salary_withdrawals
                $check_table = $conn->query("SHOW TABLES LIKE 'salary_withdrawals'");
                if ($check_table->num_rows == 0) {
                    throw new Exception("جدول سحبيات الرواتب غير موجود");
                }

                // إدخال سحب راتب
                $withdrawal_query = "INSERT INTO salary_withdrawals 
                                   (employee_id, amount, date, notes, withdrawal_type) 
                                   VALUES (?, ?, ?, ?, ?)";
                $withdrawal_stmt = $conn->prepare($withdrawal_query);
                if (!$withdrawal_stmt) {
                    throw new Exception("خطأ في تحضير استعلام السحبيات: " . $conn->error);
                }

                $withdrawal_stmt->bind_param(
                    "idsss", 
                    $related_id,
                    $amount,
                    $date,
                    $description,
                    $withdrawal_type
                );

                if (!$withdrawal_stmt->execute()) {
                    throw new Exception("خطأ في تنفيذ استعلام السحبيات: " . $withdrawal_stmt->error);
                }

                $withdrawal_id = $conn->insert_id;
                $log = "تم سحب راتب للموظف ID: $related_id - المبلغ: $amount";

                // تسجيل في السجل (إذا كان الجدول موجود)
                $check_logs = $conn->query("SHOW TABLES LIKE 'expense_logs'");
                if ($check_logs->num_rows > 0) {
                    $log_query = "INSERT INTO expense_logs 
                                 (expense_id, action, details) 
                                 VALUES (?, 'salary_withdrawal', ?)";
                    $log_stmt = $conn->prepare($log_query);

                    if ($log_stmt) {
                        $log_stmt->bind_param("is", $withdrawal_id, $log);
                        $log_stmt->execute();
                    }
                }

            } else {
                // إدخال مصروف عادي في جدول expenses
                $query = "INSERT INTO expenses 
                         (expense_type, related_id, description, amount, date) 
                         VALUES (?, ?, ?, ?, ?)";
                         
                $stmt = $conn->prepare($query);
                if (!$stmt) {
                    throw new Exception("خطأ في تحضير استعلام المصروفات: " . $conn->error);
                }

                $stmt->bind_param(
                    "sisds", 
                    $expense_type,
                    $related_id,
                    $description,
                    $amount,
                    $date
                );

                if (!$stmt->execute()) {
                    throw new Exception("خطأ في تنفيذ استعلام المصروفات: " . $stmt->error);
                }

                $expense_id = $conn->insert_id;

                // معالجة خاصة لكل نوع
                switch ($expense_type) {
                    case 'utilities':
                        $log = "تم دفع فاتورة $description";
                        break;

                    case 'purchases':
                        $log = "تم الشراء من المورد ID: $related_id";
                        break;

                    default:
                        $log = "تم إضافة مصروف: $description";
                }

                // تسجيل في السجل (إذا كان الجدول موجود)
                $check_logs = $conn->query("SHOW TABLES LIKE 'expense_logs'");
                if ($check_logs->num_rows > 0) {
                    $log_query = "INSERT INTO expense_logs 
                                 (expense_id, action, details) 
                                 VALUES (?, 'create', ?)";
                    $log_stmt = $conn->prepare($log_query);

                    if ($log_stmt) {
                        $log_stmt->bind_param("is", $expense_id, $log);
                        $log_stmt->execute();
                    }
                }
            }

            $conn->commit();
            $_SESSION['success'] = "تم حفظ المصروف بنجاح";

        } catch (Exception $e) {
            $conn->rollback();
            $_SESSION['error'] = "خطأ: " . $e->getMessage();
        }
    } else {
        $_SESSION['error'] = implode('<br>', $errors);
    }

    header("Location: expenses.php");
    exit();
}
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إضافة مصروف</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
            font-weight: 600;
        }
        
        .container {
            background-color: white;
            border-radius: 15px;
            box-shadow: 0 0.15rem 1.75rem 0 rgba(58, 59, 69, 0.15);
            padding: 30px;
            margin-top: 30px;
            margin-bottom: 30px;
        }
        
        .page-header {
            border-bottom: 1px solid #e3e6f0;
            padding-bottom: 15px;
            margin-bottom: 25px;
        }
        
        .page-title {
            color: #5a5c69;
            font-weight: 700;
            font-size: 1.75rem;
            text-align: center;
        }
        
        .form-label {
            font-weight: 600;
            margin-bottom: 0.5rem;
        }
        
        .form-label.required:after {
            content: " *";
            color: red;
        }
        
        .btn-custom {
            border-radius: 8px;
            font-weight: 600;
            padding: 10px 20px;
            transition: all 0.3s;
        }
        
        .btn-submit {
            background-color: #28a745;
            border-color: #28a745;
            color: white;
        }
        
        .btn-submit:hover {
            background-color: #218838;
            border-color: #1e7e34;
        }
        
        .form-control, .form-select {
            font-weight: 500;
            border-radius: 8px;
            border: 1px solid #d1d3e2;
            padding: 0.75rem;
        }
        
        .form-control:focus, .form-select:focus {
            border-color: #4e73df;
            box-shadow: 0 0 0 0.2rem rgba(78, 115, 223, 0.25);
        }
        
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 0.15rem 1.75rem 0 rgba(58, 59, 69, 0.15);
        }
        
        .card-header {
            background-color: #4e73df;
            color: white;
            border-radius: 15px 15px 0 0 !important;
            font-weight: 700;
        }
        
        .alert {
            font-weight: 600;
            border-radius: 8px;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 15px;
                margin: 15px;
            }
            
            .page-title {
                font-size: 1.5rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-plus me-2"></i>إضافة مصروف جديد
            </h1>
        </div>
        
        <?php if (isset($_SESSION['error'])): ?>
            <div class="alert alert-danger">
                <?= $_SESSION['error']; unset($_SESSION['error']); ?>
            </div>
        <?php endif; ?>
        
        <?php if (isset($_SESSION['success'])): ?>
            <div class="alert alert-success">
                <?= $_SESSION['success']; unset($_SESSION['success']); ?>
            </div>
        <?php endif; ?>
        
        <div class="card">
            <div class="card-header">
                <h4 class="mb-0">بيانات المصروف</h4>
            </div>
            <div class="card-body">
                <form method="post">
                    <div class="row g-3">
                        <!-- نوع المصروف -->
                        <div class="col-md-6">
                            <label class="form-label required">نوع المصروف</label>
                            <select name="expense_type" id="expense_type" class="form-select" required>
                                <option value="">-- اختر نوع المصروف --</option>
                                <option value="salaries">رواتب الموظفين</option>
                                <option value="utilities">فواتير (كهرباء/ماء/هاتف)</option>
                                <option value="purchases">مشتريات</option>
                                <option value="other">أخرى</option>
                            </select>
                        </div>
                        
                        <!-- الحقول الديناميكية -->
                        <div id="dynamic_fields" class="col-12">
                            <!-- سيتم عرض الحقول المناسبة هنا حسب النوع -->
                        </div>
                        
                        <!-- المبلغ والتاريخ -->
                        <div class="col-md-6">
                            <label class="form-label required">المبلغ</label>
                            <input type="number" name="amount" class="form-control" step="0.01" min="0.01" required>
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label required">التاريخ</label>
                            <input type="date" name="date" class="form-control" max="<?= date('Y-m-d') ?>" value="<?= date('Y-m-d') ?>" required>
                        </div>
                        
                        <div class="col-12 text-center">
                            <button type="submit" class="btn btn-submit btn-custom">
                                <i class="fas fa-save me-2"></i>حفظ المصروف
                            </button>
                            <a href="expenses.php" class="btn btn-secondary btn-custom">
                                <i class="fas fa-arrow-left me-2"></i>إلغاء
                            </a>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script src="<?= BASE_URL ?>assets/js/jquery.min.js"></script>
    <script>
    $(document).ready(function() {
        // عند تغيير نوع المصروف
        $('#expense_type').change(function() {
            const type = $(this).val();
            let html = '';
            
            switch(type) {
                case 'salaries':
                    html = `
                        <div class="col-md-6">
                            <label class="form-label required">الموظف</label>
                            <select name="related_id" class="form-select" required>
                                <option value="">-- اختر الموظف --</option>
                                <?php foreach($employees as $id => $name): ?>
                                    <option value="<?= $id ?>"><?= htmlspecialchars($name) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        <div class="col-md-6">
                            <label class="form-label">وصف إضافي</label>
                            <input type="text" name="description" class="form-control" placeholder="وصف إضافي (اختياري)">
                        </div>
                        <div class="col-md-6">
                            <label class="form-label">نوع السحب</label>
                            <select name="withdrawal_type" class="form-select">
                                <option value="cash">سحب من الراتب</option>
                                <option value="bank_transfer">تحويل بنكي</option>
                            </select>
                        </div>
                    `;
                    break;
                    
                case 'utilities':
                    html = `
                        <div class="col-md-6">
                            <label class="form-label required">نوع الفاتورة</label>
                            <select name="description" class="form-select" required>
                                <option value="">-- اختر نوع الفاتورة --</option>
                                <option value="فاتورة كهرباء">فاتورة كهرباء</option>
                                <option value="فاتورة ماء">فاتورة ماء</option>
                                <option value="فاتورة هاتف">فاتورة هاتف</option>
                                <option value="فاتورة إنترنت">فاتورة إنترنت</option>
                            </select>
                        </div>
                    `;
                    break;
                    
                case 'purchases':
                    html = `
                        <div class="col-md-6">
                            <label class="form-label required">المورد</label>
                            <select name="related_id" class="form-select" required>
                                <option value="">-- اختر المورد --</option>
                                <?php foreach($suppliers as $id => $name): ?>
                                    <option value="<?= $id ?>"><?= htmlspecialchars($name) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        <div class="col-md-6">
                            <label class="form-label required">وصف المشتريات</label>
                            <input type="text" name="description" class="form-control" placeholder="وصف المشتريات" required>
                        </div>
                    `;
                    break;
                    
                default:
                    html = `
                        <div class="col-12">
                            <label class="form-label required">وصف المصروف</label>
                            <input type="text" name="description" class="form-control" placeholder="أدخل وصف المصروف" required>
                        </div>
                    `;
            }
            
            $('#dynamic_fields').html(html);
        });
    });
    </script>
</body>
</html>
