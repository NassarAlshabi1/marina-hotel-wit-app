<?php
/*-------------------------------------------------
|  ملاحظات النوبات – نسخة نهائية 2025
|  تصميم عصري بخط Tajawal وألوان متناسقة
|  أزرار «تمت المهمة» + «حذف» داخل كل بطاقة
-------------------------------------------------*/
require_once '../../includes/header2.php';
require_once '../../includes/db.php';

// صلاحيات
if (!check_permission('view_notes')) {
    header('Location: ' . admin_url('dash.php?error=ليس لديك صلاحية'));
    exit();
}

/*==========  معالجة الإجراءات  ==========*/
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    switch ($_POST['action']) {
        case 'add':
            $title    = trim($_POST['title']);
            $content  = trim($_POST['content']);
            $priority = $_POST['priority'];
            $shift    = $_POST['shift_type'];
            $expires  = !empty($_POST['expires_at']) ? $_POST['expires_at'] : null;

            if ($title && $content) {
                $stmt = $conn->prepare("INSERT INTO shift_notes(title,content,priority,shift_type,expires_at,created_by)
                                        VALUES(?,?,?,?,?,?)");
                $stmt->bind_param('sssssi', $title, $content, $priority, $shift, $expires, $_SESSION['user_id']);
                $stmt->execute() ?  $success = 'تم إضافة الملاحظة بنجاح' : $error = 'خطأ أثناء الإضافة';
                $stmt->close();
            }
            break;

        case 'edit':
            $id       = (int)$_POST['id'];
            $title    = trim($_POST['title']);
            $content  = trim($_POST['content']);
            $priority = $_POST['priority'];
            $shift    = $_POST['shift_type'];
            $expires  = !empty($_POST['expires_at']) ? $_POST['expires_at'] : null;

            $stmt = $conn->prepare("UPDATE shift_notes SET title=?,content=?,priority=?,shift_type=?,expires_at=? WHERE id=?");
            $stmt->bind_param('sssssi', $title, $content, $priority, $shift, $expires, $id);
            $stmt->execute() ? $success = 'تم تحديث الملاحظة' : $error = 'خطأ أثناء التحديث';
            $stmt->close();
            break;

        case 'delete':
            $id = (int)$_POST['id'];
            $conn->query("DELETE FROM shift_notes WHERE id=$id");
            $success = 'تم حذف الملاحظة';
            break;

        case 'mark_read':
            $id = (int)$_POST['id'];
            $conn->query("UPDATE shift_notes SET is_read=1 WHERE id=$id");
            break;
    }
}

/*==========  بناء الفلاتر  ==========*/
$filter = $_GET['filter'] ?? 'all';
$where  = "WHERE status='active'";

switch ($filter) {
    case 'unread':  $where .= " AND is_read=0"; break;
    case 'high':    $where .= " AND priority='high'"; break;
    case 'my_shift':
        $h = date('H');
        $shift = ($h >= 6 && $h < 14) ? 'morning' : (($h >= 14 && $h < 22) ? 'evening' : 'night');
        $where .= " AND (shift_type='$shift' OR shift_type='all')";
        break;
}

$notes = $conn->query("SELECT * FROM shift_notes $where ORDER BY priority DESC, created_at DESC");
?>

<!-- ==================  HEADER STYLES  ================== -->
<link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@300;400;500;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
<style>
:root {
    --primary:#0d47a1;
    --danger:#c62828;
    --warning:#f9a825;
    --info:#0097a7;
    --success:#2e7d32;
}
body{font-family:'Tajawal',sans-serif;background:#f5f7fa;color:#212529}
.card{border-radius:.75rem;border:none;box-shadow:0 2px 8px rgba(0,0,0,.08)}
.card-header{background:#fff;border-bottom:1px solid #e9ecef}
.btn-group .btn{min-width:150px;font-weight:500}
.priority-high   {border-left:5px solid var(--danger)}
.priority-medium {border-left:5px solid var(--warning)}
.priority-low    {border-left:5px solid var(--info)}
.badge{font-size:.7rem}
</style>

<!-- ==================  CONTENT  ================== -->
<div class="container-fluid py-4">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <h2 class="fw-bold text-primary">
            <i class="fas fa-bell me-2"></i>ملاحظات النوبات
        </h2>
        <div>
            <button class="btn btn-success rounded-pill px-4" data-bs-toggle="modal" data-bs-target="#addNoteModal">
                <i class="fas fa-plus me-2"></i>إضافة ملاحظة
            </button>
            <a href="../dash.php" class="btn btn-outline-primary rounded-pill px-4 ms-2">
                <i class="fas fa-arrow-left me-2"></i>عودة
            </a>
        </div>
    </div>

    <!-- Alerts -->
    <?php if (isset($success)): ?>
        <div class="alert alert-success alert-dismissible fade show d-flex align-items-center">
            <i class="fas fa-check-circle me-2"></i><?= $success ?>
            <button type="button" class="btn-close ms-auto" data-bs-dismiss="alert"></button>
        </div>
    <?php elseif (isset($error)): ?>
        <div class="alert alert-danger alert-dismissible fade show d-flex align-items-center">
            <i class="fas fa-exclamation-circle me-2"></i><?= $error ?>
            <button type="button" class="btn-close ms-auto" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <!-- Filters -->
    <div class="card mb-4 shadow-sm">
        <div class="card-body">
            <div class="btn-group flex-wrap gap-2" role="group">
                <?php
                $filters = [
                    'all'      => ['label'=>'جميع الملاحظات','icon'=>'fa-list'],
                    'unread'   => ['label'=>'غير مقروءة','icon'=>'fa-eye-slash'],
                    'high'     => ['label'=>'عالية الأولوية','icon'=>'fa-exclamation-circle'],
                    'my_shift' => ['label'=>'نوبتي الحالية','icon'=>'fa-clock']
                ];
                foreach ($filters as $k=>$f):
                    $active = $filter === $k ? 'btn-primary' : 'btn-outline-primary';
                    echo "<a href='?filter=$k' class='btn rounded-pill $active'>
                            <i class='fas {$f['icon']} me-2'></i>{$f['label']}
                          </a>";
                endforeach;
                ?>
            </div>
        </div>
    </div>

    <!-- Notes Grid -->
    <div class="row">
        <?php if ($notes && $notes->num_rows): ?>
            <?php while ($n = $notes->fetch_assoc()):
                    $pClass = "priority-{$n['priority']}";
            ?>
                <div class="col-md-6 col-lg-4 mb-4">
                    <div class="card h-100 shadow-sm <?= $pClass ?> <?= !$n['is_read'] ? 'border-primary' : '' ?>">
                        <div class="card-header d-flex justify-content-between align-items-center bg-white">
                            <div class="d-flex gap-2">
                                <span class="badge badge-<?= $n['priority']==='high'?'danger':($n['priority']==='medium'?'warning text-dark':'info') ?>">
                                    <?= $n['priority']==='high'?'عالية':($n['priority']==='medium'?'متوسطة':'منخفضة') ?>
                                </span>
                                <?php if (!$n['is_read']): ?>
                                    <span class="badge bg-primary">جديد</span>
                                <?php endif; ?>
                            </div>
                        </div>

                        <div class="card-body d-flex flex-column">
                            <h6 class="fw-bold mb-2"><?= htmlspecialchars($n['title']) ?></h6>
                            <p class="text-muted" style="font-size:.95rem"><?= nl2br(htmlspecialchars($n['content'])) ?></p>

                            <div class="mt-auto small text-muted">
                                <div class="d-flex align-items-center mb-1">
                                    <i class="fas fa-user-circle me-2"></i>مستخدم #<?= $n['created_by'] ?>
                                </div>
                                <div class="d-flex align-items-center mb-1">
                                    <i class="fas fa-calendar-alt me-2"></i><?= date('Y-m-d H:i',strtotime($n['created_at'])) ?>
                                </div>
                                <div class="d-flex align-items-center">
                                    <i class="fas fa-users me-2"></i>
                                    <?= $n['shift_type']==='all'?'كل النوبات':
                                      ($n['shift_type']==='morning'?'الصباح':
                                      ($n['shift_type']==='evening'?'المساء':'الليل')) ?>
                                </div>
                                <?php if ($n['expires_at']): ?>
                                    <div class="d-flex align-items-center text-warning mt-1">
                                        <i class="fas fa-hourglass-end me-2"></i>ينتهي: <?= date('Y-m-d H:i',strtotime($n['expires_at'])) ?>
                                    </div>
                                <?php endif; ?>
                            </div>

                            <!-- أزرار الإجراءات السريعة -->
                            <div class="d-flex gap-2 mt-3">
                                <?php if (!$n['is_read']): ?>
                    <button class="btn btn-success btn-sm flex-fill rounded-pill"
                            onclick="markAsRead(<?= $n['id'] ?>)">
                        <i class="fas fa-check me-1"></i>تمّت المهمة
                    </button>
                <?php else: ?>
                    <button class="btn btn-secondary btn-sm flex-fill rounded-pill" disabled>
                        <i class="fas fa-check-double me-1"></i>مُنجزة
                    </button>
                <?php endif; ?>

                <button class="btn btn-outline-danger btn-sm flex-fill rounded-pill"
                        onclick="deleteNote(<?= $n['id'] ?>)">
                    <i class="fas fa-trash me-1"></i>حذف
                </button>
            </div>
                        </div>
                    </div>
                </div>
            <?php endwhile; ?>
        <?php else: ?>
            <div class="col-12">
                <div class="card shadow-sm text-center py-5">
                    <i class="fas fa-sticky-note fa-3x text-muted mb-3"></i>
                    <h5 class="text-muted">لا توجد ملاحظات</h5>
                    <p class="text-muted">لا توجد نتائج مطابقة للفلتر الحالي.</p>
                </div>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- ==================  MODALS  ================== -->
<!-- إضافة ملاحظة -->
<div class="modal fade" id="addNoteModal" tabindex="-1">
    <div class="modal-dialog modal-lg">
        <form method="POST">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title"><i class="fas fa-plus-circle me-2"></i>إضافة ملاحظة</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <input type="hidden" name="action" value="add">
                    <div class="mb-3">
                        <label class="form-label fw-bold">العنوان</label>
                        <input type="text" name="title" class="form-control" required>
                    </div>
                    <div class="mb-3">
                        <label class="form-label fw-bold">المحتوى</label>
                        <textarea name="content" class="form-control" rows="4" required></textarea>
                    </div>
                    <div class="row">
                        <div class="col-md-6 mb-3">
                            <label class="form-label fw-bold">الأولوية</label>
                            <select name="priority" class="form-select">
                                <option value="low">منخفضة</option>
                                <option value="medium" selected>متوسطة</option>
                                <option value="high">عالية</option>
                            </select>
                        </div>
                        <div class="col-md-6 mb-3">
                            <label class="form-label fw-bold">النوبة</label>
                            <select name="shift_type" class="form-select">
                                <option value="all" selected>كل النوبات</option>
                                <option value="morning">الصباح</option>
                                <option value="evening">المساء</option>
                                <option value="night">الليل</option>
                            </select>
                        </div>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">تاريخ الانتهاء (اختياري)</label>
                        <input type="datetime-local" name="expires_at" class="form-control">
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary rounded-pill px-4" data-bs-dismiss="modal">إلغاء</button>
                    <button type="submit" class="btn btn-success rounded-pill px-4">
                        <i class="fas fa-save me-2"></i>حفظ
                    </button>
                </div>
            </div>
        </form>
    </div>
</div>

<!-- تعديل ملاحظة -->
<div class="modal fade" id="editNoteModal" tabindex="-1">
    <div class="modal-dialog modal-lg">
        <form method="POST" id="editNoteForm">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title"><i class="fas fa-edit me-2"></i>تعديل ملاحظة</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <input type="hidden" name="action" value="edit">
                    <input type="hidden" name="id" id="edit_note_id">
                    <!-- نفس حقول الإضافة مع id مختلف -->
                    <div class="mb-3">
                        <label class="form-label fw-bold">العنوان</label>
                        <input type="text" name="title" id="edit_title" class="form-control" required>
                    </div>
                    <div class="mb-3">
                        <label class="form-label fw-bold">المحتوى</label>
                        <textarea name="content" id="edit_content" class="form-control" rows="4" required></textarea>
                    </div>
                    <div class="row">
                        <div class="col-md-6 mb-3">
                            <select name="priority" id="edit_priority" class="form-select">
                                <option value="low">منخفضة</option>
                                <option value="medium">متوسطة</option>
                                <option value="high">عالية</option>
                            </select>
                        </div>
                        <div class="col-md-6 mb-3">
                            <select name="shift_type" id="edit_shift_type" class="form-select">
                                <option value="all">كل النوبات</option>
                                <option value="morning">الصباح</option>
                                <option value="evening">المساء</option>
                                <option value="night">الليل</option>
                            </select>
                        </div>
                    </div>
                    <div class="mb-3">
                        <input type="datetime-local" name="expires_at" id="edit_expires_at" class="form-control">
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary rounded-pill px-4" data-bs-dismiss="modal">إلغاء</button>
                    <button type="submit" class="btn btn-primary rounded-pill px-4">
                        <i class="fas fa-save me-2"></i>حفظ التغييرات
                    </button>
                </div>
            </div>
        </form>
    </div>
</div>

<!-- ==================  JS  ================== -->
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
function editNote(id){
  fetch('get_note.php?id='+id).then(r=>r.json()).then(d=>{
    for(const k in d) if(document.getElementById('edit_'+k))
      document.getElementById('edit_'+k).value = (k==='expires_at'&&d[k])?d[k].replace(' ','T'):d[k];
    new bootstrap.Modal(document.getElementById('editNoteModal')).show();
  });
}
function deleteNote(id){
  if(confirm('هل أنت متأكد من حذف هذه الملاحظة؟')){
    const f=document.createElement('form'); f.method='POST';
    f.innerHTML=`<input type="hidden" name="action" value="delete"><input type="hidden" name="id" value="${id}">`;
    document.body.appendChild(f); f.submit();
  }
}
function markAsRead(id){
  const f=document.createElement('form'); f.method='POST';
  f.innerHTML=`<input type="hidden" name="action" value="mark_read"><input type="hidden" name="id" value="${id}">`;
  document.body.appendChild(f); f.submit();
}
</script>

<?php require_once '../../includes/footer.php'; ?>
