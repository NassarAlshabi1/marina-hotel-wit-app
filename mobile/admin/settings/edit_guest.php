<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// التحقق من وجود بيانات النزيل
$guest_name = '';
$guest_phone = '';
if (isset($_GET['name']) && isset($_GET['phone'])) {
    $guest_name = trim($_GET['name']);
    $guest_phone = trim($_GET['phone']);
} else {
    header("Location: guests.php");
    exit();
}

// جلب بيانات النزيل من أحدث حجز
$guest_query = "
    SELECT 
        guest_name,
        guest_phone,
        guest_email,
        guest_nationality,
        guest_id_number,
        guest_id_type,
        guest_id_issue_date,
        guest_id_issue_place,
        guest_address
    FROM bookings 
    WHERE guest_name = ? AND guest_phone = ?
    ORDER BY created_at DESC 
    LIMIT 1
";
$stmt = $conn->prepare($guest_query);
$stmt->bind_param("ss", $guest_name, $guest_phone);
$stmt->execute();
$guest_data = $stmt->get_result()->fetch_assoc();

if (!$guest_data) {
    header("Location: guests.php?error=لم يتم العثور على بيانات النزيل");
    exit();
}

// معالجة تحديث بيانات النزيل
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['update_guest'])) {
    $new_guest_name = trim($_POST['guest_name']);
    $new_guest_phone = trim($_POST['guest_phone']);
    $new_guest_email = trim($_POST['guest_email']);
    $new_guest_nationality = trim($_POST['guest_nationality']);
    $new_guest_id_number = trim($_POST['guest_id_number']);
    $new_guest_id_type = trim($_POST['guest_id_type']);
    $new_guest_id_issue_date = $_POST['guest_id_issue_date'];
    $new_guest_id_issue_place = trim($_POST['guest_id_issue_place']);
    $new_guest_address = trim($_POST['guest_address']);
    
    $errors = [];
    
    // التحقق من صحة البيانات
    if (empty($new_guest_name)) {
        $errors[] = "اسم النزيل مطلوب";
    }
    
    if (empty($new_guest_phone)) {
        $errors[] = "رقم الهاتف مطلوب";
    }
    
    // تحديث البيانات إذا لم توجد أخطاء
    if (empty($errors)) {
        // تحديث جميع الحجوزات للنزيل
        $update_query = "
            UPDATE bookings SET 
                guest_name = ?,
                guest_phone = ?,
                guest_email = ?,
                guest_nationality = ?,
                guest_id_number = ?,
                guest_id_type = ?,
                guest_id_issue_date = ?,
                guest_id_issue_place = ?,
                guest_address = ?
            WHERE guest_name = ? AND guest_phone = ?
        ";
        
        $stmt = $conn->prepare($update_query);
        $stmt->bind_param("sssssssssss", 
            $new_guest_name, $new_guest_phone, $new_guest_email, $new_guest_nationality,
            $new_guest_id_number, $new_guest_id_type, $new_guest_id_issue_date, 
            $new_guest_id_issue_place, $new_guest_address,
            $guest_name, $guest_phone
        );
        
        if ($stmt->execute()) {
            $success_message = "تم تحديث بيانات النزيل بنجاح";
            // تحديث البيانات المحلية
            $guest_data = [
                'guest_name' => $new_guest_name,
                'guest_phone' => $new_guest_phone,
                'guest_email' => $new_guest_email,
                'guest_nationality' => $new_guest_nationality,
                'guest_id_number' => $new_guest_id_number,
                'guest_id_type' => $new_guest_id_type,
                'guest_id_issue_date' => $new_guest_id_issue_date,
                'guest_id_issue_place' => $new_guest_id_issue_place,
                'guest_address' => $new_guest_address
            ];
            $guest_name = $new_guest_name;
            $guest_phone = $new_guest_phone;
        } else {
            $errors[] = "حدث خطأ أثناء تحديث البيانات";
        }
    }
}

// قائمة الجنسيات
$nationalities = ['يمني', 'صومالي', 'إثيوبي', 'جبوتي', 'سوداني', 'سوري', 'مصري', 'مصري', 'سعودي', 'إماراتي', 'كويتي', 'قطري', 'بحريني', 'عماني'];

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-user-edit me-2"></i>تعديل بيانات النزيل</h2>
                <div>
                    <a href="guests.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للنزلاء
                    </a>
                    <a href="guest_history.php?name=<?= urlencode($guest_name) ?>" class="btn btn-outline-info">
                        <i class="fas fa-history me-1"></i>تاريخ الحجوزات
                    </a>
                </div>
            </div>
        </div>
    </div>

    <?php if (isset($success_message)): ?>
        <div class="alert alert-success alert-dismissible fade show" role="alert">
            <i class="fas fa-check-circle me-2"></i><?= $success_message ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <?php if (!empty($errors)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i>
            <ul class="mb-0">
                <?php foreach ($errors as $error): ?>
                    <li><?= $error ?></li>
                <?php endforeach; ?>
            </ul>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <div class="row justify-content-center">
        <div class="col-md-10">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-user-edit me-2"></i>تعديل بيانات النزيل: <?= htmlspecialchars($guest_name) ?></h5>
                </div>
                <div class="card-body">
                    <form method="POST">
                        <div class="row">
                            <!-- البيانات الشخصية -->
                            <div class="col-12 mb-4">
                                <h6 class="text-primary border-bottom pb-2"><i class="fas fa-user me-2"></i>البيانات الشخصية</h6>
                            </div>
                            
                            <div class="col-md-6 mb-3">
                                <label for="guest_name" class="form-label">اسم النزيل *</label>
                                <input type="text" class="form-control" id="guest_name" name="guest_name" 
                                       value="<?= htmlspecialchars($guest_data['guest_name']) ?>" required>
                            </div>
                            
                            <div class="col-md-6 mb-3">
                                <label for="guest_nationality" class="form-label">الجنسية</label>
                                <select class="form-select" id="guest_nationality" name="guest_nationality">
                                    <option value="">اختر الجنسية</option>
                                    <?php foreach ($nationalities as $nationality): ?>
                                        <option value="<?= $nationality ?>" 
                                            <?= $guest_data['guest_nationality'] == $nationality ? 'selected' : '' ?>>
                                            <?= $nationality ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </div>

                            <!-- بيانات الاتصال -->
                            <div class="col-12 mb-4">
                                <h6 class="text-success border-bottom pb-2"><i class="fas fa-phone me-2"></i>بيانات الاتصال</h6>
                            </div>
                            
                            <div class="col-md-6 mb-3">
                                <label for="guest_phone" class="form-label">رقم الهاتف *</label>
                                <input type="tel" class="form-control" id="guest_phone" name="guest_phone" 
                                       value="<?= htmlspecialchars($guest_data['guest_phone']) ?>" required>
                            </div>
                            
                            <div class="col-md-6 mb-3">
                                <label for="guest_email" class="form-label">البريد الإلكتروني</label>
                                <input type="email" class="form-control" id="guest_email" name="guest_email" 
                                       value="<?= htmlspecialchars($guest_data['guest_email']) ?>">
                            </div>
                            
                            <div class="col-12 mb-3">
                                <label for="guest_address" class="form-label">العنوان</label>
                                <textarea class="form-control" id="guest_address" name="guest_address" rows="2"><?= htmlspecialchars($guest_data['guest_address']) ?></textarea>
                            </div>

                            <!-- بيانات الهوية -->
                            <div class="col-12 mb-4">
                                <h6 class="text-info border-bottom pb-2"><i class="fas fa-id-card me-2"></i>بيانات الهوية</h6>
                            </div>
                            
                            <div class="col-md-4 mb-3">
                                <label for="guest_id_type" class="form-label">نوع الهوية</label>
                                <select class="form-select" id="guest_id_type" name="guest_id_type">
                                    <option value="">اختر نوع الهوية</option>
                                    <option value="بطاقة شخصية" <?= $guest_data['guest_id_type'] == 'بطاقة شخصية' ? 'selected' : '' ?>>بطاقة شخصية</option>
                                    <option value="جواز سفر" <?= $guest_data['guest_id_type'] == 'جواز سفر' ? 'selected' : '' ?>>جواز سفر</option>
                                    <option value="رخصة قيادة" <?= $guest_data['guest_id_type'] == 'رخصة قيادة' ? 'selected' : '' ?>>رخصة قيادة</option>
                                </select>
                            </div>
                            
                            <div class="col-md-4 mb-3">
                                <label for="guest_id_number" class="form-label">رقم الهوية</label>
                                <input type="text" class="form-control" id="guest_id_number" name="guest_id_number" 
                                       value="<?= htmlspecialchars($guest_data['guest_id_number']) ?>">
                            </div>
                            
                            <div class="col-md-4 mb-3">
                                <label for="guest_id_issue_date" class="form-label">تاريخ الإصدار</label>
                                <input type="date" class="form-control" id="guest_id_issue_date" name="guest_id_issue_date" 
                                       value="<?= $guest_data['guest_id_issue_date'] ?>">
                            </div>
                            
                            <div class="col-md-6 mb-3">
                                <label for="guest_id_issue_place" class="form-label">مكان الإصدار</label>
                                <input type="text" class="form-control" id="guest_id_issue_place" name="guest_id_issue_place" 
                                       value="<?= htmlspecialchars($guest_data['guest_id_issue_place']) ?>">
                            </div>
                        </div>
                        
                        <div class="row">
                            <div class="col-12">
                                <div class="alert alert-warning">
                                    <i class="fas fa-exclamation-triangle me-2"></i>
                                    <strong>تنبيه:</strong> تحديث بيانات النزيل سيؤثر على جميع الحجوزات السابقة والحالية لهذا النزيل.
                                </div>
                            </div>
                        </div>
                        
                        <div class="text-end">
                            <a href="guests.php" class="btn btn-outline-secondary me-2">
                                <i class="fas fa-times me-1"></i>إلغاء
                            </a>
                            <button type="submit" name="update_guest" class="btn btn-primary">
                                <i class="fas fa-save me-1"></i>حفظ التغييرات
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
