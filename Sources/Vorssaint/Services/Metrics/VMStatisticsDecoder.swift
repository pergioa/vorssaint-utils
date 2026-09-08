// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import VMStatisticsCompat

struct VMStatisticsSnapshot: Equatable {
    let freePages: UInt64
    let wiredPages: UInt64
    let purgeablePages: UInt64
    let compressorPages: UInt64
    let externalPages: UInt64
    let internalPages: UInt64
    let freeTagStoragePages: UInt64
}

enum VMStatisticsDecoder {
    static let rev1Count = mach_msg_type_number_t(VORSSAINT_HOST_VM_INFO64_REV1_COUNT)
    static let rev3Count = mach_msg_type_number_t(VORSSAINT_HOST_VM_INFO64_REV3_COUNT)

    static func read() -> VMStatisticsSnapshot? {
        var raw = vorssaint_vm_statistics64_rev3_t()
        var returnedCount = mach_msg_type_number_t()
        guard vorssaint_read_vm_statistics64(&raw, &returnedCount) == KERN_SUCCESS else { return nil }
        return decode(raw, returnedCount: returnedCount)
    }

    static func decode(_ raw: vorssaint_vm_statistics64_rev3_t,
                       returnedCount: mach_msg_type_number_t) -> VMStatisticsSnapshot? {
        guard returnedCount >= rev1Count else { return nil }
        let hasTagStorageCounts = returnedCount >= rev3Count
        return VMStatisticsSnapshot(
            freePages: UInt64(raw.free_count),
            wiredPages: UInt64(raw.wire_count),
            purgeablePages: UInt64(raw.purgeable_count),
            compressorPages: UInt64(raw.compressor_page_count),
            externalPages: UInt64(raw.external_page_count),
            internalPages: UInt64(raw.internal_page_count),
            freeTagStoragePages: hasTagStorageCounts ? raw.free_tag_storage_pages : 0)
    }
}
