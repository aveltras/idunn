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

#include <idunn/logger.h>

#include "logger.hpp"

extern "C" {
auto idunn_log_debug(const char *msg) -> void { LOG_DEBUG("%s", msg); }
auto idunn_log_info(const char *msg) -> void { LOG_INFO("%s", msg); }
auto idunn_log_warning(const char *msg) -> void { LOG_WARNING("%s", msg); }
auto idunn_log_error(const char *msg) -> void { LOG_ERROR("%s", msg); }
}
