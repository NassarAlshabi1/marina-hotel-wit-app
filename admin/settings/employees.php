<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

$message = '';

// معالجة إضافة موظف جديد
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_employee'])) {
    $name = trim($_POST['name']);
    $position = trim($_POST['position']);
    $salary = (float)$_POST['salary'];
    $phone = trim($_POST['phone']);
    $hire_date = $_POST['hire_date'];
    $status = $_POST['status'];

    if (!empty($name) && !empty($position) && $salary > 0) {
        $stmt = $conn->prepare("INSERT INTO employees (name, position, salary, phone, hire_date, status) VALUES (?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("ssdsss", $name, $position, $salary, $phone, $hire_date, $status);
        
        if ($stmt->execute()) {
            $message = "<div class='alert alert-success'>تم إضافة الموظف بنجاح</div>";
        } else {
            $message = "<div class='alert alert-danger'>حدث خطأ: " . $conn->error . "</div>";
        }
    } else {
        $message = "<div class='alert alert-danger'>يرجى تعبئة جميع الحقول المطلوبة</div>";
    }
}

// معالجة تحديث حالة الموظف
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['update_status'])) {
    $employee_id = (int)$_POST['employee_id'];
    $new_status = $_POST['new_status'];
    
    $stmt = $conn->prepare("UPDATE employees SET status = ? WHERE id = ?");
    $stmt->bind_param("si", $new_status, $employee_id);
    
    if ($stmt->execute()) {
        $message = "<div class='alert alert-success'>تم تحديث حالة الموظف بنجاح</div>";
    } else {
        $message = "<div class='alert alert-danger'>حدث خطأ في التحديث</div>";
    }
}

// إنشاء جدول الموظفين إذا لم يكن موجوداً
$create_table = "CREATE TABLE IF NOT EXISTS employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    position VARCHAR(100) NOT NULL,
    salary DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    phone VARCHAR(20),
    hire_date DATE,
    status ENUM('active', 'inactive', 'terminated') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)";
$conn->query($create_table);

// جلب قائمة الموظفين
$employees_query = "SELECT * FROM employees ORDER BY name";
$employees_result = $conn->query($employees_query);
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إدارة الموظفين - فندق مارينا</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f8f9fa;
            direction: rtl;
            text-align: right;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .card {
            background: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            border: none;
        }
        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px 20px;
            border-radius: 10px 10px 0 0;
            border: none;
        }
        .card-body {
            padding: 20px;
        }
        .btn {
            padding: 8px 16px;
            border-radius: 5px;
            border: none;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            margin: 2px;
            transition: all 0.3s ease;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-success {
            background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
            color: white;
        }
        .btn-warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
        }
        .btn-danger {
            background: linear-gradient(135deg, #ff416c 0%, #ff4b2b 100%);
            color: white;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        .form-control, .form-select {
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            width: 100%;
            margin-bottom: 10px;
        }
        .form-control:focus, .form-select:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.2);
        }
        .table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        .table th, .table td {
            padding: 12px;
            text-align: right;
            border-bottom: 1px solid #ddd;
        }
        .table th {
            background-color: #f8f9fa;
            font-weight: bold;
        }
        .table tr:hover {
            background-color: #f5f5f5;
        }
        .status-active {
            color: #28a745;
            font-weight: bold;
        }
        .status-inactive {
            color: #ffc107;
            font-weight: bold;
        }
        .status-terminated {
            color: #dc3545;
            font-weight: bold;
        }
        .alert {
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .alert-success {
            background-color: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        .alert-danger {
            background-color: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        .row {
            display: flex;
            flex-wrap: wrap;
            margin: -10px;
        }
        .col-md-3, .col-md-4, .col-md-6 {
            padding: 10px;
        }
        .col-md-3 { flex: 0 0 25%; }
        .col-md-4 { flex: 0 0 33.333%; }
        .col-md-6 { flex: 0 0 50%; }
        @media (max-width: 768px) {
            .col-md-3, .col-md-4, .col-md-6 { flex: 0 0 100%; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
            <h2 style="color: #2c3e50; margin: 0;">إدارة الموظفين</h2>
            <a href="../dash.php" class="btn btn-primary">
                <i class="fas fa-arrow-right"></i> العودة للوحة التحكم
            </a>
        </div>

        <?php echo $message; ?>

        <!-- نموذج إضافة موظف جديد -->
        <div class="card">
            <div class="card-header">
                <h5 style="margin: 0;"><i class="fas fa-user-plus"></i> إضافة موظف جديد</h5>
            </div>
            <div class="card-body">
                <form method="post">
                    <div class="row">
                        <div class="col-md-4">
                            <label>اسم الموظف *</label>
                            <input type="text" name="name" class="form-control" required placeholder="أدخل اسم الموظف">
                        </div>
                        <div class="col-md-4">
                            <label>المنصب *</label>
                            <input type="text" name="position" class="form-control" required placeholder="أدخل المنصب">
                        </div>
                        <div class="col-md-4">
                            <label>الراتب *</label>
                            <input type="number" name="salary" class="form-control" required placeholder="0.00" step="0.01">
                        </div>
                    </div>
                    <div class="row">
                        <div class="col-md-4">
                            <label>رقم الهاتف</label>
                            <input type="text" name="phone" class="form-control" placeholder="رقم الهاتف">
                        </div>
                        <div class="col-md-4">
                            <label>تاريخ التوظيف</label>
                            <input type="date" name="hire_date" class="form-control" value="<?= date('Y-m-d') ?>">
                        </div>
                        <div class="col-md-4">
                            <label>الحالة</label>
                            <select name="status" class="form-select">
                                <option value="active">نشط</option>
                                <option value="inactive">غير نشط</option>
                                <option value="terminated">منتهي الخدمة</option>
                            </select>
                        </div>
                    </div>
                    <div style="text-align: center; margin-top: 20px;">
                        <button type="submit" name="add_employee" class="btn btn-success">
                            <i class="fas fa-save"></i> حفظ الموظف
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- قائمة الموظفين -->
        <div class="card">
            <div class="card-header">
                <h5 style="margin: 0;"><i class="fas fa-users"></i> قائمة الموظفين</h5>
            </div>
            <div class="card-body">
                <?php if ($employees_result && $employees_result->num_rows > 0): ?>
                    <div style="overflow-x: auto;">
                        <table class="table">
                            <thead>
                                <tr>
                                    <th>#</th>
                                    <th>الاسم</th>
                                    <th>المنصب</th>
                                    <th>الراتب</th>
                                    <th>الهاتف</th>
                                    <th>تاريخ التوظيف</th>
                                    <th>الحالة</th>
                                    <th>الإجراءات</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php 
                                $counter = 1;
                                while ($employee = $employees_result->fetch_assoc()): 
                                ?>
                                    <tr>
                                        <td><?= $counter++ ?></td>
                                        <td><?= htmlspecialchars($employee['name']) ?></td>
                                        <td><?= htmlspecialchars($employee['position']) ?></td>
                                        <td><?= number_format($employee['salary'], 2) ?> ر.ي</td>
                                        <td><?= htmlspecialchars($employee['phone']) ?></td>
                                        <td><?= $employee['hire_date'] ? date('Y-m-d', strtotime($employee['hire_date'])) : '-' ?></td>
                                        <td>
                                            <span class="status-<?= $employee['status'] ?>">
                                                <?php
                                                switch($employee['status']) {
                                                    case 'active': echo 'نشط'; break;
                                                    case 'inactive': echo 'غير نشط'; break;
                                                    case 'terminated': echo 'منتهي الخدمة'; break;
                                                    default: echo $employee['status'];
                                                }
                                                ?>
                                            </span>
                                        </td>
                                        <td>
                                            <form method="post" style="display: inline;">
                                                <input type="hidden" name="employee_id" value="<?= $employee['id'] ?>">
                                                <select name="new_status" onchange="this.form.submit()" class="form-select" style="width: auto; display: inline-block;">
                                                    <option value="">تغيير الحالة</option>
                                                    <option value="active" <?= $employee['status'] == 'active' ? 'selected' : '' ?>>نشط</option>
                                                    <option value="inactive" <?= $employee['status'] == 'inactive' ? 'selected' : '' ?>>غير نشط</option>
                                                    <option value="terminated" <?= $employee['status'] == 'terminated' ? 'selected' : '' ?>>منتهي الخدمة</option>
                                                </select>
                                                <input type="hidden" name="update_status" value="1">
                                            </form>
                                        </td>
                                    </tr>
                                <?php endwhile; ?>
                            </tbody>
                        </table>
                    </div>
                <?php else: ?>
                    <div class="alert alert-info" style="text-align: center;">
                        <i class="fas fa-info-circle"></i> لا يوجد موظفين مسجلين في النظام
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</body>
</html>

<?php $conn->close(); ?>
