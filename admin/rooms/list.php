<?php
include '../../includes/db.php';
include '../../includes/header2.php';

$result = $conn->query("SELECT * FROM rooms ORDER BY room_number");
?>

<div class="container mt-4">
    <h2 class="mb-4">قائمة الغرف</h2>
    
    <div class="mb-3">
        <a href="add.php" class="btn btn-success">
            <i class="fas fa-plus"></i> إضافة غرفة جديدة
        </a>
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
                        <td><?= number_format($row['price']) ?> </td>
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

<?php include '../../includes/footer.php'; ?>