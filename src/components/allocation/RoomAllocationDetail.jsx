import React from 'react';
import { BedDouble, Users, UserX, Info, Phone } from 'lucide-react';

const statusStyles = {
    Occupied: 'bg-red-500/10 text-red-500 dark:bg-red-500/20 dark:text-red-400',
    Vacant: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Maintenance: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
};

const RoomAllocationDetail = ({ room, allocations, onDeallocate }) => {
    return (
        <div>
            <h2 className="text-2xl font-bold font-heading mb-1">Room {room.room_number} Details</h2>
            <div className="flex items-center space-x-4 text-sm text-base-content-secondary mb-6">
                <span>Type: {room.type}</span>
                <span className="flex items-center">
                    <Users className="w-4 h-4 mr-1.5" />
                    Capacity: {room.occupants}
                </span>
                <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[room.status]}`}>
                    {room.status}
                </span>
            </div>

            <h3 className="text-lg font-semibold mb-4">Current Occupants ({allocations.length})</h3>
            
            {allocations.length > 0 ? (
                <ul className="space-y-3">
                    {allocations.map(alloc => (
                        <li key={alloc.id} className="flex items-center justify-between p-3 bg-base-200/50 dark:bg-dark-base-300/50 rounded-lg">
                            <div>
                                <p className="font-semibold">{alloc.students.full_name}</p>
                                <p className="text-sm text-base-content-secondary">{alloc.students.course}</p>
                                {alloc.students.contact && (
                                    <p className="flex items-center text-sm text-base-content-secondary mt-1">
                                        <Phone className="w-3 h-3 mr-1.5" />
                                        {alloc.students.contact}
                                    </p>
                                )}
                            </div>
                            <button
                                onClick={() => onDeallocate(alloc.id, alloc.students.full_name)}
                                className="p-2 text-red-500/70 hover:text-red-500 hover:bg-red-500/10 rounded-full transition-colors"
                                title="Deallocate Student"
                            >
                                <UserX className="w-5 h-5" />
                            </button>
                        </li>
                    ))}
                </ul>
            ) : (
                <div className="text-center py-10 px-6 bg-base-200/50 dark:bg-dark-base-300/50 rounded-lg">
                    <BedDouble className="mx-auto h-10 w-10 text-base-content-secondary/50" />
                    <h3 className="mt-2 text-md font-semibold">This room is vacant.</h3>
                    <p className="mt-1 text-sm text-base-content-secondary">Use the "Allocate" button on the left to assign a student.</p>
                </div>
            )}

            {room.status === 'Maintenance' && (
                 <div className="mt-6 p-4 bg-yellow-500/10 text-yellow-700 dark:text-yellow-300 rounded-lg flex items-start">
                    <Info className="w-5 h-5 mr-3 mt-0.5 flex-shrink-0" />
                    <div>
                        <h4 className="font-semibold">Under Maintenance</h4>
                        <p className="text-sm">This room is currently under maintenance and cannot be allocated.</p>
                    </div>
                </div>
            )}
        </div>
    );
};

export default RoomAllocationDetail;
