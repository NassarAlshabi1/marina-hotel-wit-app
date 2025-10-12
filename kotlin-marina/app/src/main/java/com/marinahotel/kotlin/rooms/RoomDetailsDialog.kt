package com.marinahotel.kotlin.rooms

import android.app.Dialog
import android.os.Bundle
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.DialogFragment
import com.marinahotel.kotlin.databinding.DialogRoomDetailsBinding

class RoomDetailsDialog : DialogFragment() {
    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val binding = DialogRoomDetailsBinding.inflate(layoutInflater)
        val room = arguments?.getParcelable<RoomArgs>(ARG_ROOM)
        binding.roomNumber.text = "غرفة ${room?.number ?: ""}"
        binding.roomStatus.text = room?.status ?: ""
        binding.roomType.text = room?.type ?: ""
        return AlertDialog.Builder(requireContext())
            .setView(binding.root)
            .setPositiveButton("إغلاق") { dialog, _ -> dialog.dismiss() }
            .create()
    }

    companion object {
        private const val ARG_ROOM = "arg_room"
        fun newInstance(room: RoomItem): RoomDetailsDialog {
            val args = Bundle().apply {
                putParcelable(ARG_ROOM, RoomArgs(room.number, room.status, room.type))
            }
            return RoomDetailsDialog().apply { arguments = args }
        }
    }
}

data class RoomArgs(val number: String, val status: String, val type: String) : android.os.Parcelable {
    constructor(parcel: android.os.Parcel) : this(
        parcel.readString().orEmpty(),
        parcel.readString().orEmpty(),
        parcel.readString().orEmpty()
    )

    override fun writeToParcel(parcel: android.os.Parcel, flags: Int) {
        parcel.writeString(number)
        parcel.writeString(status)
        parcel.writeString(type)
    }

    override fun describeContents(): Int = 0

    companion object CREATOR : android.os.Parcelable.Creator<RoomArgs> {
        override fun createFromParcel(parcel: android.os.Parcel): RoomArgs = RoomArgs(parcel)
        override fun newArray(size: Int): Array<RoomArgs?> = arrayOfNulls(size)
    }
}
