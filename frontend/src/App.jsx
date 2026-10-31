
import { useEffect } from "react";
import { testSupabaseConnection } from "./lib/testSupabase";

function App() {
  useEffect(() => {
    testSupabaseConnection();
  }, []);

  return (
    <div>
      <h1>Subscription Management System</h1>
      <p>Supabase connection test</p>
    </div>
  );
}

export default App;
