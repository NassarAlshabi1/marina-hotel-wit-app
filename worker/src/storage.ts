// ═══════════════════════════════════════════════════════════════
//  storage.ts — Cloudflare R2 File Storage
//  Upload, download, delete files with metadata tracking
// ═══════════════════════════════════════════════════════════════

import type { R2Bucket } from '@cloudflare/workers-types';
import type { AuthContext } from './auth';

// ─── Types ────────────────────────────────────────────────────

interface FileMetadata {
  id: string;
  filename: string;
  content_type: string;
  size: number;
  uploaded_by: string;
  uploaded_at: number;
  entity?: string;
  entity_id?: string;
}

// ─── Allowed MIME types ───────────────────────────────────────

const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'application/pdf',
  'text/plain',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

// ─── Upload Handler ───────────────────────────────────────────

export async function handleUpload(
  request: Request,
  bucket: R2Bucket | null,
  ctx: AuthContext
): Promise<Response> {
  if (!bucket) {
    return jsonError('R2 storage not configured. Enable R2 in Cloudflare Dashboard.', 503);
  }
  try {
    const formData = await request.formData();
    const file = formData.get('file') as File | null;

    if (!file) {
      return jsonError('No file provided', 400);
    }

    // ─── Validation ──────────────────────────────────────────
    if (file.size > MAX_FILE_SIZE) {
      return jsonError(`File too large. Max ${MAX_FILE_SIZE / 1024 / 1024}MB`, 413);
    }

    if (!ALLOWED_MIME_TYPES.has(file.type)) {
      return jsonError(`File type not allowed: ${file.type}`, 415);
    }

    // ─── Generate file ID ────────────────────────────────────
    const fileId = crypto.randomUUID();
    const ext = file.name.split('.').pop() || '';
    const r2Key = `uploads/${fileId}.${ext}`;

    // ─── Upload to R2 ────────────────────────────────────────
    const arrayBuffer = await file.arrayBuffer();
    await bucket.put(r2Key, arrayBuffer, {
      httpMetadata: {
        contentType: file.type,
        contentDisposition: `attachment; filename="${file.name}"`,
      },
      customMetadata: {
        fileId,
        filename: file.name,
        uploadedBy: ctx.userId,
        uploadedAt: new Date().toISOString(),
      },
    });

    const metadata: FileMetadata = {
      id: fileId,
      filename: file.name,
      content_type: file.type,
      size: file.size,
      uploaded_by: ctx.userId,
      uploaded_at: Math.floor(Date.now() / 1000),
    };

    return jsonResponse(metadata, 201);
  } catch (err) {
    console.error('[FILES/UPLOAD] Error:', err);
    return jsonError('Upload failed', 500);
  }
}

// ─── Download Handler ─────────────────────────────────────────

export async function handleDownload(
  fileId: string,
  bucket: R2Bucket | null
): Promise<Response> {
  if (!bucket) {
    return jsonError('R2 storage not configured.', 503);
  }
  try {
    // R2 keys are stored as uploads/{fileId}.{ext}
    // We need to list objects with prefix to find the exact key
    const listed = await bucket.list({ prefix: `uploads/${fileId}`, limit: 1 });

    if (listed.objects.length === 0) {
      return jsonError('File not found', 404);
    }

    const r2Key = listed.objects[0].key;
    const object = await bucket.get(r2Key);

    if (!object) {
      return jsonError('File not found', 404);
    }

    const headers = new Headers();
    headers.set('Content-Type', object.httpMetadata?.contentType || 'application/octet-stream');
    headers.set('Content-Disposition', object.httpMetadata?.contentDisposition || 'attachment');
    headers.set('Content-Length', object.size.toString());
    headers.set('Cache-Control', 'private, max-age=3600');

    return new Response(object.body, { headers });
  } catch (err) {
    console.error('[FILES/DOWNLOAD] Error:', err);
    return jsonError('Download failed', 500);
  }
}

// ─── Delete Handler ───────────────────────────────────────────

export async function handleDelete(
  fileId: string,
  bucket: R2Bucket | null,
  ctx: AuthContext
): Promise<Response> {
  if (!bucket) {
    return jsonError('R2 storage not configured.', 503);
  }
  try {
    const listed = await bucket.list({ prefix: `uploads/${fileId}`, limit: 1 });

    if (listed.objects.length === 0) {
      return jsonError('File not found', 404);
    }

    const r2Key = listed.objects[0].key;
    await bucket.delete(r2Key);

    return jsonResponse({ deleted: true, id: fileId });
  } catch (err) {
    console.error('[FILES/DELETE] Error:', err);
    return jsonError('Delete failed', 500);
  }
}

// ─── Helpers ──────────────────────────────────────────────────

function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

function jsonError(message: string, status: number = 400): Response {
  return jsonResponse({ error: message }, status);
}
