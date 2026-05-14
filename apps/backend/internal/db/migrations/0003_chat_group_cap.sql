-- +goose Up
-- +goose StatementBegin

-- v1.1 Chat Design lock: group cap = 8 members (humans + agent).
-- Enforced via trigger because the max is across both user_id and agent_id
-- rows in chat_participants.

CREATE OR REPLACE FUNCTION enforce_chat_member_cap() RETURNS trigger AS $$
DECLARE
    cnt INT;
    chat_kind TEXT;
BEGIN
    SELECT type INTO chat_kind FROM chats WHERE id = NEW.chat_id;
    IF chat_kind = 'direct' THEN
        SELECT COUNT(*) INTO cnt FROM chat_participants WHERE chat_id = NEW.chat_id;
        IF cnt + 1 > 2 THEN
            RAISE EXCEPTION 'direct chat capped at 2 participants';
        END IF;
    ELSIF chat_kind = 'group' THEN
        SELECT COUNT(*) INTO cnt FROM chat_participants WHERE chat_id = NEW.chat_id;
        IF cnt + 1 > 8 THEN
            RAISE EXCEPTION 'group chat capped at 8 participants';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chat_participants_cap
    BEFORE INSERT ON chat_participants
    FOR EACH ROW EXECUTE FUNCTION enforce_chat_member_cap();

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS chat_participants_cap ON chat_participants;
DROP FUNCTION IF EXISTS enforce_chat_member_cap();

-- +goose StatementEnd
