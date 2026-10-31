
import { supabase } from "../lib/supabase";

// 1. Register a new user
export async function signUp(fullName, email, password) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: fullName,
      },
    },
  });

  if (error) throw error;

  return data;
}

// 2. Login
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) throw error;

  return data;
}

// 3. Logout
export async function signOut() {
  const { error } = await supabase.auth.signOut();

  if (error) throw error;
}

// 4. Get current authenticated user
export async function getCurrentUser() {
  const { data, error } = await supabase.auth.getUser();

  if (error) throw error;

  return data.user;
}

// 5. Get current session
export async function getSession() {
  const { data, error } = await supabase.auth.getSession();

  if (error) throw error;

  return data.session;
}

// 6. Listen for authentication changes
export function listenToAuthChanges(callback) {
  const { data } = supabase.auth.onAuthStateChange(
    (_event, session) => {
      callback(session);
    }
  );

  return data.subscription;
}
