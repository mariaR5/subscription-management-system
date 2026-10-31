
import { useEffect, useState } from "react";

import {
  signUp,
  signIn,
  signOut,
  getSession,
  listenToAuthChanges,
} from "./services/authService";

function App() {
  const [mode, setMode] = useState("login");

  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const [user, setUser] = useState(null);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  // Restore session and listen for login/logout changes
  useEffect(() => {
    getSession()
      .then((session) => {
        setUser(session?.user ?? null);
      })
      .catch((error) => {
        console.error(error);
      });

    const subscription = listenToAuthChanges((session) => {
      setUser(session?.user ?? null);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  // Handle login or signup
  async function handleSubmit(event) {
    event.preventDefault();

    setLoading(true);
    setMessage("");

    try {
      if (mode === "signup") {
        const data = await signUp(fullName, email, password);

        if (data.session) {
          setMessage("Account created successfully!");
        } else {
          setMessage(
            "Account created. Check your email for the confirmation link."
          );
        }
      } else {
        await signIn(email, password);

        setMessage("Login successful!");
      }
    } catch (error) {
      setMessage(error.message);
    } finally {
      setLoading(false);
    }
  }

  // Handle logout
  async function handleLogout() {
    try {
      await signOut();
      setMessage("Logged out successfully.");
    } catch (error) {
      setMessage(error.message);
    }
  }

  // Logged-in screen
  if (user) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Subscription Management System</h1>

        <h2>Welcome!</h2>

        <p>Email: {user.email}</p>

        <p>User ID: {user.id}</p>

        <button onClick={handleLogout}>
          Logout
        </button>

        <p>{message}</p>
      </div>
    );
  }

  // Login and signup screen
  return (
    <div style={{ maxWidth: "400px", margin: "50px auto" }}>
      <h1>Subscription Management System</h1>

      <h2>
        {mode === "login" ? "Login" : "Create Account"}
      </h2>

      <form onSubmit={handleSubmit}>
        {mode === "signup" && (
          <input
            type="text"
            placeholder="Full Name"
            value={fullName}
            onChange={(event) =>
              setFullName(event.target.value)
            }
            required
          />
        )}

        <br />
        <br />

        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(event) =>
            setEmail(event.target.value)
          }
          required
        />

        <br />
        <br />

        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(event) =>
            setPassword(event.target.value)
          }
          minLength={6}
          required
        />

        <br />
        <br />

        <button type="submit" disabled={loading}>
          {loading
            ? "Please wait..."
            : mode === "login"
            ? "Login"
            : "Sign Up"}
        </button>
      </form>

      <p>{message}</p>

      <button
        onClick={() => {
          setMode(mode === "login" ? "signup" : "login");
          setMessage("");
        }}
      >
        {mode === "login"
          ? "Create an account"
          : "Already have an account? Login"}
      </button>
    </div>
  );
}

export default App;
