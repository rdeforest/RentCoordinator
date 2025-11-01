-- Migration: Add discount_applied column to rent_periods table
-- This stores the calculated credit applied from work hours

ALTER TABLE rent_periods ADD COLUMN discount_applied REAL DEFAULT 0;
