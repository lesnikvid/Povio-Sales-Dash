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

-- Indexes for performance
CREATE INDEX idx_goals_user_id ON goals(user_id);
CREATE INDEX idx_whales_user_id ON whales(user_id);

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
