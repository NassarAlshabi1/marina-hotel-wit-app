<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

$result = $conn->query("SELECT * FROM rooms ORDER BY room_number");

// تضمين الهيدر بعد انتهاء معالجة البيانات
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-bed me-2"></i>قائمة الغرف</h2>
                <div>
                    <a href="../settings/index.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للإعدادات
                    </a>
                    <a href="add.php" class="btn btn-success">
                        <i class="fas fa-plus me-1"></i>إضافة غرفة جديدة
                    </a>
                </div>
            </div>
        </div>
    </div>

    <div class="table-responsive">
        <table class="table table-striped table-bordered">
            <thead class="table-dark">
                <tr>
                    <th>#</th>
                    <th>رقم الغرفة</th>
                    <th>النوع</th>
                    <th>السعر</th>
                    <th>الحالة</th>
                    <th>إجراءات</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($result->num_rows > 0): ?>
                    <?php $counter = 1; ?>
                    <?php while ($row = $result->fetch_assoc()): ?>
                    <tr>
                        <td><?= $counter++ ?></td>
                        <td><?= htmlspecialchars($row['room_number']) ?></td>
                        <td><?= htmlspecialchars($row['type']) ?></td>
                        <td><?= number_format($row['price'], 2) ?> </td>
                        <td>
                            <span class="badge <?= [
                                'شاغرة' => 'bg-success',
                                'محجوزة' => 'bg-danger',
                                'صيانة' => 'bg-warning text-dark'
                            ][$row['status']] ?? 'bg-secondary' ?>">
                                <?= htmlspecialchars($row['status']) ?>
                            </span>
                        </td>
                        <td>
                            <div class="btn-group">
                                <a href="view.php?room_number=<?= urlencode($row['room_number']) ?>" 
                                   class="btn btn-sm btn-info"
                                   title="عرض التفاصيل">
                                    <i class="fas fa-eye"></i>
                                </a>
                                <a href="edit.php?room_number=<?= urlencode($row['room_number']) ?>" 
                                   class="btn btn-sm btn-primary"
                                   title="تعديل">
                                    <i class="fas fa-edit"></i>
                                </a>
                                <a href="delete.php?room_number=<?= urlencode($row['room_number']) ?>" 
                                   class="btn btn-sm btn-danger"
                                   title="حذف"
                                   onclick="return confirm('هل أنت متأكد من حذف الغرفة رقم <?= $row['room_number'] ?>؟')">
                                    <i class="fas fa-trash"></i>
                                </a>
                            </div>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                <?php else: ?>
                    <tr>
                        <td colspan="6" class="text-center py-4">
                            لا توجد غرف مسجلة
                        </td>
                    </tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>