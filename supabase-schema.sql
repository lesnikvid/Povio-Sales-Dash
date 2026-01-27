-- Povio Sales Dashboard Database Schema
-- Run this in Supabase SQL Editor (SQL Editor tab in left sidebar)

-- Goals Table
CREATE TABLE goals (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    number TEXT NOT NULL,
    title TEXT NOT NULL,
    target TEXT NOT NULL,
    deadline TEXT,
    category TEXT,
    milestones JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Whales Table
CREATE TABLE whales (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    industry TEXT NOT NULL,
    health TEXT NOT NULL,
    arr TEXT NOT NULL,
    ltv TEXT NOT NULL,
    contract_end TEXT,
    account_manager TEXT,
    last_qbr TEXT,
    next_qbr TEXT,
    expansion TEXT,
    churn_risk TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Whale Notes Table (for timestamped history)
CREATE TABLE whale_notes (
    id SERIAL PRIMARY KEY,
    whale_id INTEGER NOT NULL REFERENCES whales(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    note_type TEXT NOT NULL DEFAULT 'general', -- 'general', 'meeting', 'update', etc.
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by TEXT NOT NULL
);

-- Indexes for performance
CREATE INDEX idx_goals_user_id ON goals(user_id);
CREATE INDEX idx_whales_user_id ON whales(user_id);
CREATE INDEX idx_whale_notes_whale_id ON whale_notes(whale_id);
CREATE INDEX idx_whale_notes_created_at ON whale_notes(created_at DESC);

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers to auto-update updated_at timestamps
CREATE TRIGGER update_goals_updated_at BEFORE UPDATE ON goals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_whales_updated_at BEFORE UPDATE ON whales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
