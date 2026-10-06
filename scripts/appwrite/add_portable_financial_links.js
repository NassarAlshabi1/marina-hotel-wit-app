#!/usr/bin/env node
'use strict';

/**
 * Adds the provider-neutral financial relationship attributes introduced by
 * Flutter schema 70. The operation is idempotent and never modifies existing
 * attributes or historical documents.
 *
 * Required environment variable:
 *   APPWRITE_API_KEY
 *
 * Optional environment variables:
 *   APPWRITE_ENDPOINT
 *   APPWRITE_PROJECT_ID
 *   APPWRITE_DATABASE_ID
 *
 * Usage:
 *   npm run add:portable-financial-links -- --dry-run
 *   npm run add:portable-financial-links
 */

const ENDPOINT =
  process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID =
  process.env.APPWRITE_PROJECT_ID || '6a4408f300217885fd7b';
const DATABASE_ID =
  process.env.APPWRITE_DATABASE_ID || '6a4409b50019dd39dde5';
const API_KEY = process.env.APPWRITE_API_KEY || '';

const UUID_SIZE = 36;
const ATTRIBUTES = [
  { collectionId: 'expenses', key: 'withdrawalUuid' },
  { collectionId: 'salary_withdrawals', key: 'expenseUuid' },
  { collectionId: 'salary_payments', key: 'cycleUuid' },
  { collectionId: 'salary_carry_over_logs', key: 'employeeUuid' },
];

const dryRun = process.argv.includes('--dry-run');

function assertConfiguration() {
  if (!API_KEY && !dryRun) {
    throw new Error(
      'APPWRITE_API_KEY is required. Pass it as an environment variable; ' +
        'never place it in this script.',
    );
  }

  for (const [name, value] of Object.entries({
    APPWRITE_ENDPOINT: ENDPOINT,
    APPWRITE_PROJECT_ID: PROJECT_ID,
    APPWRITE_DATABASE_ID: DATABASE_ID,
  })) {
    if (!value.trim()) throw new Error(`${name} must not be empty.`);
  }
}

function isCompatible(attribute) {
  return (
    attribute.type === 'string' &&
    Number(attribute.size) >= UUID_SIZE &&
    attribute.required === false &&
    attribute.array !== true
  );
}

function describe(attribute) {
  return [
    `type=${attribute.type}`,
    `size=${attribute.size ?? 'unknown'}`,
    `required=${attribute.required}`,
    `array=${attribute.array === true}`,
    `status=${attribute.status ?? 'unknown'}`,
  ].join(', ');
}

function isNotFound(error) {
  return error?.code === 404 || error?.type === 'attribute_not_found';
}

async function getExistingAttribute(databases, collectionId, key) {
  try {
    return await databases.getAttribute(DATABASE_ID, collectionId, key);
  } catch (error) {
    if (isNotFound(error)) return null;
    throw error;
  }
}

async function waitUntilAvailable(databases, collectionId, key) {
  const timeoutAt = Date.now() + 90_000;

  while (Date.now() < timeoutAt) {
    const attribute = await databases.getAttribute(
      DATABASE_ID,
      collectionId,
      key,
    );

    if (attribute.status === 'available') return attribute;
    if (attribute.status === 'failed') {
      throw new Error(`Appwrite reported a failed status for ${key}.`);
    }

    await new Promise((resolve) => setTimeout(resolve, 1500));
  }

  throw new Error(`Timed out waiting for ${key} to become available.`);
}

async function main() {
  assertConfiguration();

  console.log('Adding portable financial relationship attributes to Appwrite');
  console.log(`Endpoint: ${ENDPOINT}`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Database: ${DATABASE_ID}`);
  console.log(`Mode: ${dryRun ? 'dry run' : 'apply'}\n`);

  if (dryRun && !API_KEY) {
    console.log('Planned attributes:');
    for (const { collectionId, key } of ATTRIBUTES) {
      console.log(
        `  - ${collectionId}.${key}: string(${UUID_SIZE}), optional, scalar`,
      );
    }
    console.log('\nNo API calls were made because APPWRITE_API_KEY was not set.');
    return;
  }

  const { Client, Databases } = require('node-appwrite');
  const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);
  const databases = new Databases(client);

  let added = 0;
  let skipped = 0;
  let failed = 0;

  for (const { collectionId, key } of ATTRIBUTES) {
    const label = `${collectionId}.${key}`;

    try {
      const existing = await getExistingAttribute(
        databases,
        collectionId,
        key,
      );

      if (existing) {
        if (!isCompatible(existing)) {
          throw new Error(
            `Existing attribute is incompatible (${describe(existing)}). ` +
              'It was not modified automatically.',
          );
        }

        console.log(`SKIP ${label}: already compatible (${describe(existing)})`);
        skipped += 1;
        continue;
      }

      if (dryRun) {
        console.log(
          `PLAN ${label}: create string(${UUID_SIZE}), optional, scalar`,
        );
        added += 1;
        continue;
      }

      // No default is supplied: historical documents remain valid and the
      // missing relationship is represented as null/absent rather than "".
      await databases.createStringAttribute(
        DATABASE_ID,
        collectionId,
        key,
        UUID_SIZE,
        false,
      );

      const created = await waitUntilAvailable(databases, collectionId, key);
      if (!isCompatible(created)) {
        throw new Error(`Created attribute is incompatible (${describe(created)}).`);
      }

      console.log(`ADD  ${label}: available (${describe(created)})`);
      added += 1;
    } catch (error) {
      console.error(`FAIL ${label}: ${error.message}`);
      failed += 1;
    }
  }

  console.log(
    `\nResult: ${added} ${dryRun ? 'planned' : 'added'}, ` +
      `${skipped} already present, ${failed} failed.`,
  );

  if (failed > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`Fatal: ${error.message}`);
  process.exitCode = 1;
});
