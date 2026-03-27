/*
 * Copyright (C) 2026 Romain Viallard
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#pragma once

#include <cstdint>
#include <cstdio>
#include <utility>

#define IDUNN_LEVEL_DEBUG 1
#define IDUNN_LEVEL_INFO 2
#define IDUNN_LEVEL_WARNING 3
#define IDUNN_LEVEL_ERROR 4

#ifndef IDUNN_LOG_THRESHOLD
#ifdef NDEBUG
#define IDUNN_LOG_THRESHOLD IDUNN_LEVEL_INFO
#else
#define IDUNN_LOG_THRESHOLD IDUNN_LEVEL_DEBUG
#endif
#endif

enum class LogLevel : std::uint8_t { Debug, Info, Warning, Error };

#ifdef NDEBUG
constexpr LogLevel MIN_LOG_LEVEL = LogLevel::Info;
#else
constexpr LogLevel MIN_LOG_LEVEL = LogLevel::Debug;
#endif

struct Logger {

  template <LogLevel Level> static void log(const char *message) {
    if constexpr (Level >= MIN_LOG_LEVEL) {
      std::printf("%s[%s]%s %s\n", getColor(Level), getLevelName(Level),
                  "\033[0m", message);
    }
  }

  template <LogLevel Level, typename... Args>
  static void log(const char *fmt, Args &&...args) {
    if constexpr (Level >= MIN_LOG_LEVEL) {
      std::printf("%s[%s]%s ", getColor(Level), getLevelName(Level), "\033[0m");
      std::printf(fmt, std::forward<Args>(args)...);
      std::printf("\n");
    }
  }

  static constexpr auto getLevelName(LogLevel level) -> const char * {
    switch (level) {
    case LogLevel::Error:
      return "ERROR";
    case LogLevel::Warning:
      return "WARN";
    case LogLevel::Info:
      return "INFO";
    case LogLevel::Debug:
      return "DEBUG";
    }
  }

  static constexpr auto getColor(LogLevel level) -> const char * {
    switch (level) {
    case LogLevel::Error:
      return "\033[31m";
    case LogLevel::Warning:
      return "\033[33m";
    case LogLevel::Info:
      return "\033[32m";
    case LogLevel::Debug:
      return "\033[36m";
    }
  }
};

#define IDUNN_LOG_INTERNAL(LevelNum, LevelEnum, fmt, ...)                      \
  do {                                                                         \
    if constexpr (LevelNum >= IDUNN_LOG_THRESHOLD) {                           \
      Logger::log<LogLevel::LevelEnum>(fmt __VA_OPT__(, ) __VA_ARGS__);        \
    }                                                                          \
  } while (0)

#define LOG_DEBUG(fmt, ...)                                                    \
  IDUNN_LOG_INTERNAL(IDUNN_LEVEL_DEBUG, Debug, fmt __VA_OPT__(, ) __VA_ARGS__)
#define LOG_INFO(fmt, ...)                                                     \
  IDUNN_LOG_INTERNAL(IDUNN_LEVEL_INFO, Info, fmt __VA_OPT__(, ) __VA_ARGS__)
#define LOG_WARNING(fmt, ...)                                                  \
  IDUNN_LOG_INTERNAL(IDUNN_LEVEL_WARNING, Warning,                             \
                     fmt __VA_OPT__(, ) __VA_ARGS__)
#define LOG_ERROR(fmt, ...)                                                    \
  IDUNN_LOG_INTERNAL(IDUNN_LEVEL_ERROR, Error, fmt __VA_OPT__(, ) __VA_ARGS__)
