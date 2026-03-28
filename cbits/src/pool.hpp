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

#include "logger.hpp"

#include <cassert>
#include <cstdint>
#include <functional>
#include <iterator>
#include <utility>

template <typename T>
struct Handle {
  explicit Handle(uint64_t raw) : value(raw) {}
  Handle() { value = UINT64_MAX; }
  auto operator==(Handle other) const -> bool { return value == other.value; }
  auto operator!=(Handle other) const -> bool { return value != other.value; }
  [[nodiscard]] auto index() const -> uint32_t { return static_cast<uint32_t>(value & 0xFFFFFFFF); }
  [[nodiscard]] auto gen() const -> uint32_t { return static_cast<uint32_t>(value >> 32); }
  [[nodiscard]] auto isValid() const -> bool { return value != 0; }
  [[nodiscard]] auto raw() const -> uint64_t { return value; }
  static auto make(uint32_t idx, uint32_t gen) -> Handle {
    return Handle{((uint64_t)gen << 32) | idx};
  }

private:
  uint64_t value;
};

template <typename Item>
struct Pool {
  static_assert(std::is_move_constructible_v<Item>, "Item must be movable");

  Pool(uint32_t initialCapacity, std::function<void(Item &item)> &&onFree) : onFree(std::move(onFree)) {
    LOG_DEBUG("Pool");
    dense.reserve(initialCapacity);
    sparse.reserve(initialCapacity);
  }

  [[nodiscard]] auto getSize() const -> uint32_t {
    return dense.size();
  }

  auto clear() -> void {
    LOG_DEBUG("Pool::clear");
    for (Item &item : *this) {
      onFree(item);
    }
  }

  template <typename... Args>
  auto allocate(Item **ppItem, Args &&...args) -> Handle<Item> {
    if (freeHead == UINT32_MAX) {
      uint32_t oldCap = sparse.size();
      uint32_t newCap = std::max(16U, oldCap * 2);
      sparse.resize(newCap);
      dense.reserve(newCap);

      for (uint32_t i = oldCap; i < newCap - 1; ++i) {
        sparse[i].denseIdx = i + 1;
        sparse[i].gen = 0;
      }

      sparse[newCap - 1].denseIdx = UINT32_MAX;
      freeHead = oldCap;
    }

    uint32_t sparseIdx = freeHead;
    SparseSlot &sSlot = sparse[sparseIdx];
    freeHead = sSlot.denseIdx;

    auto denseIdx = static_cast<uint32_t>(dense.size());
    LOG_DEBUG("ALLOCATE");
    dense.emplace_back(sparseIdx, std::forward<Args>(args)...);

    sSlot.denseIdx = denseIdx;
    sSlot.gen++;

    if (ppItem) {
      *ppItem = &dense[denseIdx].item;
    }

    return Handle<Item>::make(sparseIdx, sSlot.gen);
  };

  auto free(Handle<Item> &handle) -> void {
    uint32_t sparseIdx = handle.index();
    assert(sparseIdx < sparse.size() && sparse[sparseIdx].gen == handle.gen());

    uint32_t denseIdxToRemove = sparse[sparseIdx].denseIdx;
    onFree(dense[denseIdxToRemove].item);

    auto lastDenseIdx = static_cast<uint32_t>(dense.size() - 1);

    if (denseIdxToRemove != lastDenseIdx) {
      dense[denseIdxToRemove] = std::move(dense[lastDenseIdx]);
      sparse[dense[denseIdxToRemove].sparseIdx].denseIdx = denseIdxToRemove;
    }

    dense.pop_back();

    sparse[sparseIdx].denseIdx = freeHead;
    freeHead = sparseIdx;
  }

  auto get(Handle<Item> &handle) -> Item * {
    uint32_t sparseIdx = handle.index();
    assert(sparseIdx < sparse.capacity());
    SparseSlot &sparseSlot = sparse[sparseIdx];
    return sparseSlot.gen == handle.gen()
               ? &dense[sparseSlot.denseIdx].item
               : nullptr;
  }

  auto begin() { return DenseIterator(dense.begin()); }
  auto end() { return DenseIterator(dense.end()); }

private:
  struct DenseSlot {
    Item item;
    uint32_t sparseIdx;

    template <typename... Args>
    DenseSlot(uint32_t sparseIdx, Args &&...args) : item(std::forward<Args>(args)...), sparseIdx(sparseIdx) {}
  };

  struct SparseSlot {
    uint32_t denseIdx;
    uint32_t gen;
  };

  struct DenseIterator {
    using iterator_category = std::forward_iterator_tag;
    using value_type = Item;
    using pointer = Item *;
    using reference = Item &;

    typename std::vector<DenseSlot>::iterator it;

    explicit DenseIterator(typename std::vector<DenseSlot>::iterator startIt) : it(startIt) {}

    auto operator*() const -> reference { return it->item; }
    auto operator->() -> pointer { return &(it->item); }

    auto operator++() -> DenseIterator & {
      ++it;
      return *this;
    }
    auto operator++(int) -> DenseIterator {
      DenseIterator tmp = *this;
      ++it;
      return tmp;
    }

    auto operator==(const DenseIterator &other) const -> bool { return it == other.it; }
    auto operator!=(const DenseIterator &other) const -> bool { return it != other.it; }
  };

  uint32_t freeHead = UINT32_MAX;
  std::vector<DenseSlot> dense;
  std::vector<SparseSlot> sparse;
  std::function<void(Item &item)> onFree;
};
