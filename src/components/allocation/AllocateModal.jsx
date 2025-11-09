import React, { useState, useEffect, useMemo } from 'react';
import toast from 'react-hot-toast';
import { supabase } from '../../lib/supabase';
import Modal from '../ui/Modal';
import { Loader, Search, UserPlus, Phone } from 'lucide-react';
import { useDebounce } from '../../hooks/useDebounce';

const AllocateModal = ({ isOpen, onClose, room, onAllocationSuccess }) => {
    const [students, setStudents] = useState([]);
    const [loading, setLoading] = useState(true);
    const [formLoading, setFormLoading] = useState(false);
    const [selectedStudentId, setSelectedStudentId] = useState('');
    const [searchTerm, setSearchTerm] = useState('');
    const debouncedSearchTerm = useDebounce(searchTerm, 300);

    useEffect(() => {
        if (isOpen) {
            const fetchUnallocatedStudents = async () => {
                setLoading(true);
                try {
                    // This should be an RPC for efficiency, but this works for now.
                    const { data, error } = await supabase.rpc('get_unallocated_students');

                    if (error) throw error;
                    
                    // The RPC should return students already ordered by full_name
                    setStudents(data || []);
                } catch (error) {
                    toast.error(`Failed to fetch students: ${error.message}`);
                    setStudents([]);
                } finally {
                    setLoading(false);
                }
            };
            fetchUnallocatedStudents();
        }
    }, [isOpen]);

    const filteredStudents = useMemo(() => {
        if (!debouncedSearchTerm) return students;
        const lowercasedTerm = debouncedSearchTerm.toLowerCase();
        return students.filter(student =>
            student.full_name.toLowerCase().includes(lowercasedTerm) ||
            student.email.toLowerCase().includes(lowercasedTerm) ||
            (student.contact && student.contact.toLowerCase().includes(lowercasedTerm))
        );
    }, [students, debouncedSearchTerm]);

    const handleAllocate = async () => {
        if (!selectedStudentId) {
            toast.error('Please select a student to allocate.');
            return;
        }
        setFormLoading(true);
        try {
            const { error } = await supabase.rpc('allocate_room', {
                p_student_id: selectedStudentId,
                p_room_id: room.id,
            });

            if (error) throw error;
            onAllocationSuccess();
        } catch (error) {
            toast.error(`Allocation failed: ${error.message}`);
        } finally {
            setFormLoading(false);
        }
    };

    return (
        <Modal title={`Allocate Room ${room.room_number}`} isOpen={isOpen} onClose={onClose}>
            <div className="space-y-4">
                <p className="text-sm text-base-content-secondary">
                    Select a student to allocate to this room. The list shows only unallocated students, sorted alphabetically.
                </p>
                
                <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-base-content-secondary" />
                    <input
                        type="text"
                        placeholder="Search by name, email, or mobile..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-10 pr-4 py-2 rounded-lg bg-base-200 dark:bg-dark-base-300 focus:ring-2 focus:ring-primary focus:border-primary transition"
                    />
                </div>

                <div className="max-h-64 overflow-y-auto border border-base-300 dark:border-dark-base-300 rounded-lg">
                    {loading ? (
                        <div className="flex justify-center items-center p-8">
                            <Loader className="animate-spin" />
                        </div>
                    ) : filteredStudents.length > 0 ? (
                        <ul className="divide-y divide-base-200 dark:divide-dark-base-300">
                            {filteredStudents.map(student => (
                                <li
                                    key={student.id}
                                    onClick={() => setSelectedStudentId(student.id)}
                                    className={`p-3 cursor-pointer transition-colors ${selectedStudentId === student.id ? 'bg-primary/10 text-primary' : 'hover:bg-base-200/60 dark:hover:bg-dark-base-300/60'}`}
                                >
                                    <div className="flex justify-between items-center">
                                        <span className="font-semibold">{student.full_name}</span>
                                        <span className="text-xs text-base-content-secondary">{student.course}</span>
                                    </div>
                                    <p className="text-sm text-base-content-secondary">{student.email}</p>
                                    {student.contact && (
                                        <p className="flex items-center text-sm text-base-content-secondary mt-1">
                                            <Phone className="w-3 h-3 mr-1.5" />
                                            {student.contact}
                                        </p>
                                    )}
                                </li>
                            ))}
                        </ul>
                    ) : (
                        <div className="text-center p-8 text-base-content-secondary">
                            <UserPlus className="w-8 h-8 mx-auto mb-2" />
                            <p>No unallocated students found.</p>
                        </div>
                    )}
                </div>

                <div className="flex justify-end pt-4 space-x-3">
                    <button type="button" onClick={onClose} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-lg text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                    <button
                        type="button"
                        onClick={handleAllocate}
                        disabled={formLoading || !selectedStudentId}
                        className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50"
                    >
                        {formLoading ? <Loader className="animate-spin h-4 w-4 mr-2" /> : <UserPlus className="h-4 w-4 mr-2" />}
                        Allocate Student
                    </button>
                </div>
            </div>
        </Modal>
    );
};

export default AllocateModal;
