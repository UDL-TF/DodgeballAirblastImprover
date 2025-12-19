#if defined _tfdb_logging_included
  #endinput
#endif
#define _tfdb_logging_included

#include <json>
#include <sourcemod>
#include <files>
#include "env_variables"
#include "sourcetvmanager"

/**
 * Ensures the log directory exists.
 */
stock void TFDB_EnsureLogDir()
{
  char path[PLATFORM_MAX_PATH];

  // Ensure base logs directory exists
  BuildPath(Path_SM, path, sizeof(path), "logs");
  if (!DirExists(path))
  {
    CreateDirectory(path, 493);
  }

  // Ensure anticheat subdirectory exists
  BuildPath(Path_SM, path, sizeof(path), "logs/anticheat");
  if (!DirExists(path))
  {
    if (!CreateDirectory(path, 493))
    {
      LogError("Failed to create log directory: %s", path);
    }
  }
}

/**
 * LogEntry methodmap to build structured logs.
 */
methodmap LogEntry < JSON_Object
{
  /**
   * Creates a new LogEntry.
   */
public   LogEntry()
  {
    return view_as<LogEntry>(new JSON_Object());
  }

  /**
   * Adds a string value to the log entry.
   */
public   LogEntry WithString(const char[] key, const char[] value)
  {
    this.SetString(key, value);
    return this;
  }

  /**
   * Adds an integer value to the log entry.
   */
public   LogEntry WithInt(const char[] key, int value)
  {
    this.SetInt(key, value);
    return this;
  }

  /**
   * Adds a float value to the log entry.
   */
public   LogEntry WithFloat(const char[] key, float value)
  {
    this.SetFloat(key, value);
    return this;
  }

  /**
   * Adds a boolean value to the log entry.
   */
public   LogEntry WithBool(const char[] key, bool value)
  {
    this.SetBool(key, value);
    return this;
  }

public   LogEntry WithFileName(const char[] filename)
  {
    this.SetString("__filename", filename);
    return this;
  }

  /**
   * Logs an INFO message.
   */
public   void Info(const char[] msg, any...)
  {
    char formatted[2048];
    VFormat(formatted, sizeof(formatted), msg, 3);
    this._Write("INFO", formatted);
  }

  /**
   * Logs a WARN message.
   */
public   void Warn(const char[] msg, any...)
  {
    char formatted[2048];
    VFormat(formatted, sizeof(formatted), msg, 3);
    this._Write("WARN", formatted);
  }

  /**
   * Logs an ERROR message.
   */
public   void Error(const char[] msg, any...)
  {
    char formatted[2048];
    VFormat(formatted, sizeof(formatted), msg, 3);
    this._Write("ERROR", formatted);
  }

  /**
   * Logs a DEBUG message.
   */
public   void Debug(const char[] msg, any...)
  {
    char formatted[2048];
    VFormat(formatted, sizeof(formatted), msg, 3);
    this._Write("DEBUG", formatted);
  }

  /**
   * Internal method to write the log to file.
   */
public   void _Write(const char[] level, const char[] msg)
  {
    // Create a new object to ensure field order: level, time, msg, then others
    JSON_Object ordered = new JSON_Object();

    ordered.SetString("level", level);
    ordered.SetString("msg", msg);

    char timeStr[64];
    FormatTime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%S", GetTime());
    ordered.SetString("time", timeStr);

    char MatchID[128];
    char RoundID[128];

    GetEnvironmentVariable("MATCH_ID", MatchID, sizeof(MatchID));
    if (MatchID[0] != '\0')
    {
      ordered.SetString("match_id", MatchID);
    }

    GetEnvironmentVariable("ROUND_ID", RoundID, sizeof(RoundID));
    if (RoundID[0] != '\0')
    {
      ordered.SetString("round_id", RoundID);
    }

    char customFile[PLATFORM_MAX_PATH];
    bool hasCustomFile = false;
    if (this.GetType("__filename") == JSON_Type_String)
    {
      this.GetString("__filename", customFile, sizeof(customFile));
      this.Remove("__filename");
      hasCustomFile = true;
    }

    // Build the log file path using BuildPath
    char path[PLATFORM_MAX_PATH];
    char date[32];
    FormatTime(date, sizeof(date), "%Y-%m-%d_%H", GetTime());

    // If a custom filename was provided, use it. Absolute paths are used as-is,
    // otherwise the file will be placed under logs/anticheat/.
    if (hasCustomFile)
    {
      if (customFile[0] == '/')
      {
        Format(path, sizeof(path), "%s", customFile);
      }
      else
      {
        BuildPath(Path_SM, path, sizeof(path), "logs/anticheat/%s", customFile);
      }
    }
    else
    {
      if (MatchID[0] != '\0' && RoundID[0] != '\0')
      {
        // Use match_id and round_id in filename if both are available
        if (StrEqual(level, "DEBUG"))
        {
          BuildPath(Path_SM, path, sizeof(path), "logs/anticheat/tfdb_%s_%s_debug.log", MatchID, RoundID);
        }
        else {
          BuildPath(Path_SM, path, sizeof(path), "logs/anticheat/tfdb_%s_%s.log", MatchID, RoundID);
        }
      }
      else
      {
        // Fall back to date-based filename
        if (StrEqual(level, "DEBUG"))
        {
          BuildPath(Path_SM, path, sizeof(path), "logs/anticheat/tfdb_%s_debug.log", date);
        }
        else {
          BuildPath(Path_SM, path, sizeof(path), "logs/anticheat/tfdb_%s.log", date);
        }
      }
    }

    if (SourceTV_IsRecording())
    {
      int tick = SourceTV_GetRecordingTick();
      ordered.SetInt("demo_tick", tick);
    }

    // Move all other fields from 'this' to 'ordered' to preserve order
    // We iterate and remove from 'this' to transfer ownership of objects
    while (this.Length > 0)
    {
      char key[128];
      this.GetKey(0, key, sizeof(key));

      // Skip if it conflicts with priority fields (shouldn't happen usually)
      if (StrEqual(key, "level") || StrEqual(key, "msg") || StrEqual(key, "time"))
      {
        this.Remove(key);
        continue;
      }

      JSONCellType type = this.GetType(key);
      switch (type)
      {
        case JSON_Type_String:
        {
          int len    = this.GetSize(key);
          char[] val = new char[len];
          this.GetString(key, val, len);
          ordered.SetString(key, val);
        }
        case JSON_Type_Int: ordered.SetInt(key, this.GetInt(key));
        case JSON_Type_Float: ordered.SetFloat(key, this.GetFloat(key));
        case JSON_Type_Bool: ordered.SetBool(key, this.GetBool(key));
        case JSON_Type_Object:
        {
          // Transfer object handle
          ordered.SetObject(key, this.GetObject(key));
        }
      }

      // Remove from 'this' so we don't double-free or duplicate
      this.Remove(key);
    }

    // Encode to JSON string
    char buffer[4096];
    json_encode(ordered, buffer, sizeof(buffer));

    // Ensure log directory exists
    TFDB_EnsureLogDir();

    // Explicitly create file if it doesn't exist
    if (!FileExists(path))
    {
      File fCreate = OpenFile(path, "w");
      if (fCreate != null)
      {
        delete fCreate;
      }
    }

    File f = OpenFile(path, "a+");
    if (f != null)
    {
      f.WriteLine(buffer);
      delete f;
    }
    else {
      LogError("Failed to open log file: %s", path);
    }

    // Cleanup 'ordered' (which now owns everything)
    json_cleanup_and_delete(ordered);

    // Cleanup 'this' (which is now empty)
    JSON_Object obj = view_as<JSON_Object>(this);
    json_cleanup_and_delete(obj);
  }
}

/**
 * Starts a new log entry.
 * Usage: Log().WithInt("key", 1).Info("Message");
 */
stock LogEntry Log()
{
  return new LogEntry();
}