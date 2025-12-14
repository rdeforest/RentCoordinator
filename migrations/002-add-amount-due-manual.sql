-- Migration: Add amount_due_manual column to rent_periods table
-- Purpose: Track when amount_due is manually overridden vs calculated

ALTER TABLE rent_periods ADD COLUMN amount_due_manual BOOLEAN DEFAULT 0;
