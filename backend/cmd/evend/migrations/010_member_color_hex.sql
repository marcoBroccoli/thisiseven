-- Free-choice member colors: store #RRGGBB (or keep legacy clay/teal until rewritten).
-- Drop the one-clay-one-teal unique + check so both partners can pick any color.

alter table members drop constraint if exists members_color_check;
alter table members drop constraint if exists members_household_id_color_key;

update members set color = '#A6552F' where color = 'clay';
update members set color = '#37756D' where color = 'teal';
