/// Optional read-only infrastructure adapter; callers inject a public-key client.
library;

export 'src/supabase_roster_reader.dart'
    show SupabaseRosterReader, decodeRoster;
