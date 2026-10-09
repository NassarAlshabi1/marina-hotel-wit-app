$content = @'
<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// Create employees table if it doesn't exist
$create_table_sql = "
CREATE TABLE IF NOT EXISTS employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    basic_salary DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    status ENUM('active','inactive') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)";
$conn->query($create_table_sql);

// Handle adding new employee
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add_employee'])) {
    $name = trim($_POST['name']);
    $basic_salary = floatval($_POST['basic_salary']);
    $status = $_POST['status'];

    if (!empty($name)) {
        $stmt = $conn->prepare("INSERT INTO employees (name, basic_salary, status) VALUES (?, ?, ?)");
        $stmt->bind_param("sds", $name, $basic_salary, $status);

        if ($stmt->execute()) {
            $success_message = " „ ≈÷«›… «·„ÊŸ› »‰Ã«Õ";
        } else {
            $error_message = "ÕœÀ Œÿ√ √À‰«¡ ≈÷«›… «·„ÊŸ›";
        }
    } else {
        $error_message = "«·«”„ „ÿ·Ê»";
    }
}

// Handle employee deletion
if (isset($_GET['delete']) && is_numeric($_GET['delete'])) {
    $id = intval($_GET['delete']);
    $stmt = $conn->prepare("DELETE FROM employees WHERE id = ?");
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $success_message = " „ Õ–› «·„ÊŸ› »‰Ã«Õ";
    } else {
        $error_message = "ÕœÀ Œÿ√ √À‰«¡ Õ–› «·„ÊŸ›";
    }
}

// Get all employees
$employees = $conn->query("SELECT * FROM employees ORDER BY name");

// Include header
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-user-tie me-2"></i>≈œ«—… «·„ÊŸ›Ì‰</h2>
                <div>
                    <a href="index.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>«·⁄Êœ… ··≈⁄œ«œ« 
                    </a>
                    <a href="../dash.php" class="btn btn-outline-primary">
                        <i class="fas fa-home me-1"></i>·ÊÕ… «· Õﬂ„
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

    <?php if (isset($error_message)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i><?= $error_message ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <!-- ‰„Ê–Ã ≈÷«›… „ÊŸ› ÃœÌœ -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-user-plus me-2"></i>≈÷«›… „ÊŸ› ÃœÌœ</h5>
                </div>
                <div class="card-body">
                    <form method="POST">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label for="name" class="form-label">«”„ «·„ÊŸ› *</label>
                                <input type="text" class="form-control" id="name" name="name" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="basic_salary" class="form-label">«·—« » «·√”«”Ì</label>
                                <input type="number" step="0.01" class="form-control" id="basic_salary" name="basic_salary" value="0">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="status" class="form-label">«·Õ«·…</label>
                                <select class="form-select" id="status" name="status">
                                    <option value="active">‰‘ÿ</option>
                                    <option value="inactive">€Ì— ‰‘ÿ</option>
                                </select>
                            </div>
                        </div>
                        <div class="text-end">
                            <button type="submit" name="add_employee" class="btn btn-primary">
                                <i class="fas fa-save me-1"></i>Õ›Ÿ «·„ÊŸ›
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- ﬁ«∆„… «·„ÊŸ›Ì‰ -->
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-list me-2"></i>ﬁ«∆„… «·„ÊŸ›Ì‰</h5>
                </div>
                <div class="card-body">
                    <?php if ($employees->num_rows > 0): ?>
                        <div class="table-responsive">
                            <table class="table table-striped table-hover">
                                <thead class="table-dark">
                                    <tr>
                                        <th>#</th>
                                        <th>«·«”„</th>
                                        <th>«·—« » «·√”«”Ì</th>
                                        <th>«·Õ«·…</th>
                                        <th>«·≈Ã—«¡« </th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php
                                    $counter = 1;
                                    while ($employee = $employees->fetch_assoc()):
                                    ?>
                                    <tr>
                                        <td><?= $counter++ ?></td>
                                        <td><?= htmlspecialchars($employee['name']) ?></td>
                                        <td><?= number_format($employee['basic_salary'], 2) ?> —Ì«·</td>
                                        <td>
                                            <span class="badge <?= $employee['status'] == 'active' ? 'bg-success' : 'bg-secondary' ?>">
                                                <?= $employee['status'] == 'active' ? '‰‘ÿ' : '€Ì— ‰‘ÿ' ?>
                                            </span>
                                        </td>
                                        <td>
                                            <div class="btn-group" role="group">
                                                <a href="edit_employee.php?id=<?= $employee['id'] ?>"
                                                   class="btn btn-sm btn-outline-primary" title=" ⁄œÌ·">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <a href="?delete=<?= $employee['id'] ?>"
                                                   class="btn btn-sm btn-outline-danger"
                                                   title="Õ–›"
                                                   onclick="return confirm('Â· √‰  „ √ﬂœ „‰ Õ–› Â–« «·„ÊŸ›ø')">
                                                    <i class="fas fa-trash"></i>
                                                </a>
                                            </div>
                                        </td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php else: ?>
                        <div class="text-center py-4">
                            <i class="fas fa-users fa-3x text-muted mb-3"></i>
                            <h5 class="text-muted">·« ÌÊÃœ „ÊŸ›Ì‰ „”Ã·Ì‰</h5>
                            <p class="text-muted">ﬁ„ »≈÷«›… „ÊŸ› ÃœÌœ »«” Œœ«„ «·‰„Ê–Ã √⁄·«Â</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
'@; $content | Set-Content -Path "D:\xampp\htdocs\marina hotel\admin\settings\employees.php"; Write-Output "File updated successfully."