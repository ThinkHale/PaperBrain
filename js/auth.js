/**
 * auth.js — Supabase Auth wrapper for Illuminote
 *
 * Exposes:
 *   Auth.init()             → set up session listener, returns initial session
 *   Auth.signUp(email, pw)  → { user, error }
 *   Auth.signIn(email, pw)  → { user, error }
 *   Auth.signOut()          → void
 *   Auth.getUser()          → user | null
 *   Auth.getToken()         → access_token string | null
 *   Auth.onAuthChange(fn)   → unsubscribe function
 *   Auth.client             → raw Supabase client (for DB calls in other modules)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const { supabaseUrl, supabaseAnonKey } = window.ILLUMINOTE_CONFIG ?? {};

function hasValidConfig(url, key) {
  if (!url || !key) return false;
  if (url === "YOUR_SUPABASE_URL" || key === "YOUR_SUPABASE_ANON_KEY") return false;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && key.length > 20;
  } catch {
    return false;
  }
}

export const isConfigured = hasValidConfig(supabaseUrl, supabaseAnonKey);

export const configError =
  "Supabase is not configured. Edit config.js with your project URL and anon key, then reload.";

if (!isConfigured) {
  console.warn(
    "[Illuminote] " + configError,
  );
}

function missingConfigClient() {
  const fail = () => {
    throw new Error(configError);
  };
  return {
    auth: {
      getSession: async () => ({ data: { session: null }, error: null }),
      getUser: async () => fail(),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      signUp: async () => fail(),
      signInWithPassword: async () => fail(),
      signOut: async () => {},
    },
    functions: {
      setAuth() {},
    },
    from: () => ({ select: fail }),
    storage: {
      from: () => ({ createSignedUrls: fail }),
    },
  };
}

export const client = isConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : missingConfigClient();

let _session = null;
const _listeners = new Set();

function _notify(session) {
  _session = session;
  for (const fn of _listeners) fn(session?.user ?? null);
}

/** Call once at app start. Returns the initial user (or null). */
export async function init() {
  if (!isConfigured) return null;

  const { data: { session } } = await client.auth.getSession();
  _session = session;

  // Eagerly push the token into the functions client so invoke() uses the
  // user JWT immediately — onAuthStateChange fires asynchronously and would
  // otherwise leave the functions client using the anon key on first call.
  if (session?.access_token) {
    client.functions.setAuth(session.access_token);
  }

  client.auth.onAuthStateChange((_event, session) => {
    _notify(session);
    // Keep functions client in sync on every auth state change.
    client.functions.setAuth(session?.access_token ?? supabaseAnonKey ?? "");
  });

  return session?.user ?? null;
}


/** Register a callback invoked whenever auth state changes. Returns unsubscribe fn. */
export function onAuthChange(fn) {
  _listeners.add(fn);
  return () => _listeners.delete(fn);
}

/** Returns the current Supabase User object, or null. */
export function getUser() {
  return _session?.user ?? null;
}

/** Returns the current JWT access token, or null. */
export function getToken() {
  return _session?.access_token ?? null;
}

/**
 * Sign up with email + password.
 * Returns { user, error } — error is a string message or null.
 */
export async function signUp(email, password) {
  const { data, error } = await client.auth.signUp({ email, password });
  if (error) return { user: null, error: error.message };
  return { user: data.user, error: null };
}

/**
 * Sign in with email + password.
 * Returns { user, error }.
 */
export async function signIn(email, password) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) return { user: null, error: error.message };
  _notify(data.session);
  if (data.session?.access_token) {
    client.functions.setAuth(data.session.access_token);
  }
  return { user: data.user, error: null };
}

/** Sign out current user. */
export async function signOut() {
  await client.auth.signOut();
  _notify(null);
}

export default { client, init, onAuthChange, getUser, getToken, signUp, signIn, signOut };
