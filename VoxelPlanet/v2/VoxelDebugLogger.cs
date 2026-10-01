using System;
using System.IO;
using UnityEngine;

public static class VoxelDebugLogger
{
    private static readonly object syncRoot =
        new object();


    private static bool initialized;


    private static string logFilePath;


    // ============================================================
    // INITIALIZE
    // ============================================================

    private static void EnsureInitialized()
    {
        if (initialized)
        {
            return;
        }


        string projectDirectory =
            Directory.GetParent(
                Application.dataPath
            )?.FullName;


        if (string.IsNullOrEmpty(
            projectDirectory))
        {
            projectDirectory =
                Application.dataPath;
        }


        logFilePath =
            Path.Combine(
                projectDirectory,
                "VoxelGpuDebug.log"
            );


        initialized =
            true;
    }


    // ============================================================
    // LOG
    // ============================================================

    public static void Log(
        string message)
    {
        Write(
            "INFO",
            message
        );
    }


    // ============================================================
    // WARNING
    // ============================================================

    public static void Warning(
        string message)
    {
        Write(
            "WARNING",
            message
        );
    }


    // ============================================================
    // ERROR
    // ============================================================

    public static void Error(
        string message)
    {
        Write(
            "ERROR",
            message
        );
    }


    // ============================================================
    // WRITE
    // ============================================================

    private static void Write(
        string level,
        string message)
    {
        EnsureInitialized();


        string timestamp =
            DateTime.Now.ToString(
                "yyyy-MM-dd HH:mm:ss.fff"
            );


        string line =
            "[" +
            timestamp +
            "] [" +
            level +
            "] " +
            message;


        try
        {
            lock (syncRoot)
            {
                File.AppendAllText(
                    logFilePath,
                    line +
                    Environment.NewLine
                );
            }
        }
        catch (Exception exception)
        {
            Debug.LogError(
                "VoxelDebugLogger failed: " +
                exception.Message
            );
        }
    }


    // ============================================================
    // GET FILE PATH
    // ============================================================

    public static string GetLogFilePath()
    {
        EnsureInitialized();

        return logFilePath;
    }


    // ============================================================
    // CLEAR
    // ============================================================
    //
    // Normally we do NOT call this.
    //
    // It is here only when we explicitly want to start a new
    // debugging session.
    // ============================================================

    public static void Clear()
    {
        EnsureInitialized();


        try
        {
            lock (syncRoot)
            {
                File.WriteAllText(
                    logFilePath,
                    string.Empty
                );
            }
        }
        catch (Exception exception)
        {
            Debug.LogError(
                "VoxelDebugLogger failed to clear file: " +
                exception.Message
            );
        }
    }
}