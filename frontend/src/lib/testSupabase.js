
import { supabase } from "./supabase";

export async function testSupabaseConnection() {
  const { data, error } = await supabase
    .from("subscription_plans")
    .select("id, name, price")
    .limit(5);

  if (error) {
    console.error("Supabase connection failed:", error);
    return;
  }

  console.log("Supabase connection successful:", data);
}
