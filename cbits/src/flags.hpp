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

#include <type_traits>

namespace Idunn {

template <typename T>
  requires std::is_enum_v<T>
class Flags {
public:
  using Mask = std::underlying_type_t<T>;

  static_assert(std::is_unsigned_v<Mask>, "Flags require an enum with an unsigned underlying type.");

  constexpr Flags() noexcept : mask(0) {}

  constexpr Flags(T bit) noexcept
      : mask(static_cast<Mask>(bit)) {}

  constexpr Flags(Flags const &rhs) noexcept = default;

  explicit constexpr Flags(Mask flags) noexcept : mask(flags) {}

  constexpr auto operator<=>(Flags const &) const = default;

  constexpr auto operator!() const noexcept -> bool { return !mask; }

  constexpr auto operator&(Flags const &rhs) const noexcept -> Flags { return Flags(mask & rhs.mask); }
  constexpr auto operator|(Flags const &rhs) const noexcept -> Flags { return Flags(mask | rhs.mask); }
  constexpr auto operator^(Flags const &rhs) const noexcept -> Flags { return Flags(mask ^ rhs.mask); }
  constexpr auto operator~() const noexcept -> Flags { return Flags(static_cast<Mask>(~mask)); }

  constexpr auto operator=(Flags const &) noexcept -> Flags & = default;
  constexpr auto operator|=(Flags const &rhs) noexcept -> Flags & {
    mask |= rhs.mask;
    return *this;
  }
  constexpr auto operator&=(Flags const &rhs) noexcept -> Flags & {
    mask &= rhs.mask;
    return *this;
  }
  constexpr auto operator^=(Flags const &rhs) noexcept -> Flags & {
    mask ^= rhs.mask;
    return *this;
  }

  constexpr auto has(T bit) const noexcept -> bool {
    return (mask & static_cast<Mask>(bit)) == static_cast<Mask>(bit);
  }

  explicit constexpr operator bool() const noexcept { return mask != 0; }
  explicit constexpr operator Mask() const noexcept { return mask; }

private:
  Mask mask;
};

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator&(BitType lhs, Flags<BitType> rhs) noexcept -> Flags<BitType> { return rhs & lhs; }

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator|(BitType lhs, Flags<BitType> rhs) noexcept -> Flags<BitType> { return rhs | lhs; }

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator^(BitType lhs, Flags<BitType> rhs) noexcept -> Flags<BitType> { return rhs ^ lhs; }

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator&(BitType lhs, BitType rhs) noexcept -> Flags<BitType> {
  return Flags<BitType>(lhs) & rhs;
}

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator|(BitType lhs, BitType rhs) noexcept -> Flags<BitType> {
  return Flags<BitType>(lhs) | rhs;
}

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator^(BitType lhs, BitType rhs) noexcept -> Flags<BitType> {
  return Flags<BitType>(lhs) ^ rhs;
}

template <typename BitType>
  requires std::is_enum_v<BitType>
constexpr auto operator~(BitType bit) noexcept -> Flags<BitType> {
  return ~Flags<BitType>(bit);
}

} // namespace Idunn
