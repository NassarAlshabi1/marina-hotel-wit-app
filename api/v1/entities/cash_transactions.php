<?php
/**
 * نقطة نهاية ENTITY_NAME
 */
require_once __DIR__ . '/../config.php';
$user = ApiMiddleware::authenticate($conn);
ApiMiddleware::rateLimit($user['id'], 120, 60);
$method = $_SERVER['REQUEST_METHOD'];
$pathInfo = $_SERVER['PATH_INFO'] ?? '';
$id = $pathInfo ? trim($pathInfo, '/') : null;
try {
    switch ($method) {
        case 'GET': $id ? getItem($conn, $id) : listItems($conn); break;
        case 'POST': createItem($conn, $user); break;
        case 'PUT': if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب'); updateItem($conn, $id, $user); break;
        case 'DELETE': if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب'); deleteItem($conn, $id, $user); break;
        default: ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally { ApiMiddleware::logRequest($user, API_START_TIME); }
function listItems($conn) { $page = max(1, (int)($_GET['page'] ?? 1)); $pageSize = min(100, max(1, (int)($_GET['page_size'] ?? 50))); ApiResponse::success(['items' => [], 'pagination' => ['page' => $page, 'pageSize' => $pageSize, 'total' => 0, 'totalPages' => 0]]); }
function getItem($conn, $id) { ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'العنصر غير موجود'); }
function createItem($conn, $user) { $input = getInput(); $localUuid = $input['local_uuid'] ?? generateUuid(); ApiResponse::created(['serverId' => 1, 'localUuid' => $localUuid]); }
function updateItem($conn, $id, $user) { ApiResponse::success(['message' => 'تم التحديث بنجاح']); }
function deleteItem($conn, $id, $user) { ApiResponse::success(['message' => 'تم الحذف بنجاح']); }
