import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import { BedDouble, Loader, Users, Search } from 'lucide-react';
import PageHeader from '../components/ui/PageHeader';
import AllocateModal from '../components/allocation/AllocateModal';
import RoomAllocationDetail from '../components/allocation/RoomAllocationDetail';
import { useDebounce } from '../hooks/useDebounce';

const RoomAllocationPage = () => {
    const [rooms, setRooms] = useState([]);
    const [allocations, setAllocations] = useState({});
    const [loading, setLoading] = useState(true);
    const [selectedRoom, setSelectedRoom] = useState(null);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [modalRoom, setModalRoom] = useState(null);
    const [searchTerm, setSearchTerm] = useState('');
    const debouncedSearchTerm = useDebounce(searchTerm, 300);

    const fetchData = useCallback(async () => {
        setLoading(true);
        try {
            const [roomsRes, allocationsRes] = await Promise.all([
                supabase.from('rooms').select('*').order('room_number'),
                supabase.from('room_allocations').select('*, students(id, full_name, course, contact)').eq('is_active', true)
            ]);

            if (roomsRes.error) throw roomsRes.error;
            if (allocationsRes.error) throw allocationsRes.error;

            const roomsData = roomsRes.data || [];
            const allocationsData = allocationsRes.data || [];

            const allocationsByRoom = allocationsData.reduce((acc, alloc) => {
                if (!acc[alloc.room_id]) {
                    acc[alloc.room_id] = [];
                }
                acc[alloc.room_id].push(alloc);
                // Sort students alphabetically within each room
                acc[alloc.room_id].sort((a, b) => a.students.full_name.localeCompare(b.students.full_name));
                return acc;
            }, {});

            setRooms(roomsData);
            setAllocations(allocationsByRoom);
            
            // If a room was selected, update its details
            if (selectedRoom) {
                const updatedSelectedRoom = roomsData.find(r => r.id === selectedRoom.id);
                if (updatedSelectedRoom) {
                    setSelectedRoom(updatedSelectedRoom);
                }
            } else if (roomsData.length > 0) {
                // Select the first room by default
                setSelectedRoom(roomsData[0]);
            }

        } catch (error) {
            toast.error(`Failed to fetch data: ${error.message}`);
        } finally {
            setLoading(false);
        }
    }, [selectedRoom]);

    useEffect(() => {
        fetchData();
    }, [fetchData]);

    const handleAllocateClick = (room) => {
        setModalRoom(room);
        setIsModalOpen(true);
    };

    const handleAllocationSuccess = () => {
        toast.success('Room allocated successfully!');
        setIsModalOpen(false);
        fetchData();
    };

    const handleDeallocate = async (allocationId, studentName) => {
        if (!window.confirm(`Are you sure you want to deallocate ${studentName}?`)) return;
        
        const toastId = toast.loading('Deallocating student...');
        try {
            // This should ideally be a single RPC call to ensure atomicity
            const { error: updateAllocError } = await supabase
                .from('room_allocations')
                .update({ end_date: new Date().toISOString() })
                .eq('id', allocationId);
            
            if (updateAllocError) throw updateAllocError;

            // Manually trigger room occupancy update
            await supabase.rpc('update_room_occupancy', { p_room_id: selectedRoom.id });

            toast.success(`${studentName} deallocated successfully.`, { id: toastId });
            fetchData();
        } catch (error) {
            toast.error(`Deallocation failed: ${error.message}`, { id: toastId });
        }
    };

    const filteredRooms = rooms.filter(room =>
        room.room_number.toLowerCase().includes(debouncedSearchTerm.toLowerCase())
    );

    return (
        <>
            <PageHeader title="Room Allocation" />
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 h-[calc(100vh-200px)]">
                {/* Left Column: Room List */}
                <div className="lg:col-span-1 bg-base-100 dark:bg-dark-base-200 rounded-2xl shadow-lg flex flex-col overflow-hidden transition-colors">
                    <div className="p-4 border-b border-base-200 dark:border-dark-base-300">
                        <div className="relative">
                            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-base-content-secondary" />
                            <input
                                type="text"
                                placeholder="Search rooms..."
                                value={searchTerm}
                                onChange={(e) => setSearchTerm(e.target.value)}
                                className="w-full pl-10 pr-4 py-2 rounded-lg bg-base-200 dark:bg-dark-base-300 focus:ring-2 focus:ring-primary focus:border-primary transition"
                            />
                        </div>
                    </div>
                    <div className="overflow-y-auto flex-grow p-4">
                        {loading ? (
                            <div className="flex justify-center items-center h-full">
                                <Loader className="animate-spin" />
                            </div>
                        ) : (
                            <div className="space-y-3">
                                {filteredRooms.map(room => {
                                    const roomAllocations = allocations[room.id] || [];
                                    const isFull = roomAllocations.length >= room.occupants;
                                    return (
                                        <motion.div
                                            key={room.id}
                                            layout
                                            onClick={() => setSelectedRoom(room)}
                                            className={`p-4 rounded-xl cursor-pointer border-2 transition-all ${selectedRoom?.id === room.id ? 'bg-primary/10 border-primary dark:bg-dark-primary/20 dark:border-dark-primary' : 'bg-base-100 dark:bg-dark-base-200 hover:bg-base-200/60 dark:hover:bg-dark-base-300/60 border-transparent'}`}
                                        >
                                            <div className="flex justify-between items-start">
                                                <h3 className="font-bold text-lg">Room {room.room_number}</h3>
                                                <span className="text-sm text-base-content-secondary">{room.type}</span>
                                            </div>
                                            <div className="flex items-center text-sm text-base-content-secondary mt-2">
                                                <Users className="w-4 h-4 mr-2" />
                                                <span>{roomAllocations.length} / {room.occupants} Occupants</span>
                                            </div>
                                            <div className="mt-2">
                                                {roomAllocations.length > 0 ? (
                                                    <div className="text-xs text-base-content-secondary space-y-1">
                                                        {roomAllocations.map(a => <p key={a.id}>- {a.students.full_name}</p>)}
                                                    </div>
                                                ) : (
                                                    <p className="text-xs text-green-600 dark:text-green-400">Vacant</p>
                                                )}
                                            </div>
                                            <button
                                                onClick={(e) => { e.stopPropagation(); handleAllocateClick(room); }}
                                                disabled={isFull}
                                                className="w-full mt-4 py-2 px-4 text-sm font-semibold rounded-lg bg-primary text-primary-content hover:bg-primary-focus disabled:bg-base-300 disabled:cursor-not-allowed dark:disabled:bg-dark-base-300"
                                            >
                                                {isFull ? 'Room Full' : 'Allocate'}
                                            </button>
                                        </motion.div>
                                    );
                                })}
                            </div>
                        )}
                    </div>
                </div>

                {/* Right Column: Details */}
                <div className="lg:col-span-2 bg-base-100 dark:bg-dark-base-200 rounded-2xl shadow-lg overflow-y-auto p-6 transition-colors">
                    <AnimatePresence mode="wait">
                        <motion.div
                            key={selectedRoom?.id || 'empty'}
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, y: -20 }}
                            transition={{ duration: 0.2 }}
                        >
                            {selectedRoom ? (
                                <RoomAllocationDetail
                                    room={selectedRoom}
                                    allocations={allocations[selectedRoom.id] || []}
                                    onDeallocate={handleDeallocate}
                                />
                            ) : (
                                <div className="flex flex-col justify-center items-center h-full text-center text-base-content-secondary">
                                    <BedDouble className="w-16 h-16 mb-4" />
                                    <h3 className="text-lg font-semibold">Select a room</h3>
                                    <p>Choose a room from the list to see its details and manage occupants.</p>
                                </div>
                            )}
                        </motion.div>
                    </AnimatePresence>
                </div>
            </div>

            <AnimatePresence>
                {isModalOpen && modalRoom && (
                    <AllocateModal
                        isOpen={isModalOpen}
                        onClose={() => setIsModalOpen(false)}
                        room={modalRoom}
                        onAllocationSuccess={handleAllocationSuccess}
                    />
                )}
            </AnimatePresence>
        </>
    );
};

export default RoomAllocationPage;
