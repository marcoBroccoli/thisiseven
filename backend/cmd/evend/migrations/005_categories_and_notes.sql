-- Inbox categorization + dedupe bookkeeping.
alter table processed_emails add column if not exists note text;
alter table drafts add column if not exists category text;

-- Backfill existing drafts with a keyword heuristic; new mail gets its
-- category from the classifier.
update drafts set category = case
    when title ~* 'pay|bill|invoice|betaal|factuur|payment|owe' then 'bills'
    when title ~* 'appointment|confirm|attend|afspraak|dentist|doctor|vet' then 'appointments'
    when title ~* 'renew|subscription|abonnement|plan|price change|icloud|netflix' then 'subscriptions'
    when title ~* 'permit|tax|gemeente|belasting|insurance|verzekering|contract|statement|review' then 'admin'
    else 'other'
end
where category is null;
