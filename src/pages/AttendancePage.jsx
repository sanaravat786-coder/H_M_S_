import React, { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import { Loader, Users, FileDown } from 'lucide-react';
import PageHeader from '../components/ui/PageHeader';
import EmptyState from '../components/ui/EmptyState';
import SegmentedControl from '../components/ui/SegmentedControl';
import { useDebounce } from '../hooks/useDebounce';
import Papa from 'papaparse';

const today = new Date().toISOString().split('T')[0];

const AttendancePage = () => {
    const [filters, setFilters] = useState({ date: today, sessionType: 'NightRoll', course: '', year: '', searchTerm: '' });
    const [students, setStudents] = useState([]);
    const [records, setRecords] = useState({});
    const [session, setSession] = useState(null);
    const [loading, setLoading] = useState(false);
    const [saving, setSaving] = useState(false);
    const debouncedSearchTerm = useDebounce(filters.searchTerm, 300);

    const handleFilterChange = (key, value) => {
        setFilters(prev => ({ ...prev, [key]: value }));
    };


    const loadSessionAndStudents = useCallback(async () => {
        if (!filters.date || !filters.sessionType) {
            toast.error('Please select a date and session type.');
            return;
        }
        setLoading(true);
        try {
            // 1. Get or create the session
            const { data: sessionId, error: sessionError } = await supabase.rpc('get_or_create_session', {
                p_date: filters.date,
                p_type: filters.sessionType,
                p_course: filters.course || null,
                p_year: filters.year || null,
            });
            if (sessionError) throw sessionError;
            setSession({ id: sessionId });

            // 2. Fetch students based on filters
            let studentQuery = supabase.from('students').select('id, full_name, room_allocations(rooms(room_number))').order('full_name');
            if (filters.course) studentQuery = studentQuery.eq('course', filters.course);
            if (filters.year) studentQuery = studentQuery.eq('year', filters.year);
            const { data: studentsData, error: studentsError } = await studentQuery;
            if (studentsError) throw studentsError;
            setStudents(studentsData || []);

            // 3. Fetch existing records for this session
            const { data: recordsData, error: recordsError } = await supabase.from('attendance_records').select('*').eq('session_id', sessionId);
            if (recordsError) throw recordsError;
            
            const initialRecords = (recordsData || []).reduce((acc, rec) => {
                acc[rec.student_id] = { status: rec.status, note: rec.note || '', late_minutes: rec.late_minutes || 0 };
                return acc;
            }, {});
            setRecords(initialRecords);

        } catch (error) {
            toast.error(`Failed to load session: ${error.message}`);
        } finally {
            setLoading(false);
        }
    }, [filters.date, filters.sessionType, filters.course, filters.year]);
    
    const handleRecordChange = (studentId, key, value) => {
        setRecords(prev => ({
            ...prev,
            [studentId]: {
                ...prev[studentId],
                status: prev[studentId]?.status || 'Present', // Default to present if not set
                [key]: value
            }
        }));
    };

    const handleBulkMark = (status) => {
        const newRecords = { ...records };
        filteredStudents.forEach(student => {
            newRecords[student.id] = { ...newRecords[student.id], status };
        });
        setRecords(newRecords);
        toast.success(`Marked all visible students as ${status}`);
    };

    const handleSave = async () => {
        if (!session) {
            toast.error('No active session. Please load a session first.');
            return;
        }
        setSaving(true);
        const recordsToSave = Object.entries(records).map(([student_id, data]) => ({
            student_id,
            status: data.status,
            note: data.note || null,
            late_minutes: data.status === 'Late' ? (data.late_minutes || 0) : 0,
        }));

        try {
            const { error } = await supabase.rpc('bulk_mark_attendance', {
                p_session_id: session.id,
                p_records: recordsToSave,
            });
            if (error) throw error;
            toast.success('Attendance saved successfully!');
        } catch (error) {
            toast.error(`Failed to save: ${error.message}`);
        } finally {
            setSaving(false);
        }
    };

    const handleExport = () => {
        if (students.length === 0) {
            toast.error("No data to export.");
            return;
        }
        const exportData = students.map(student => {
            const record = records[student.id] || { status: 'Unmarked', note: '', late_minutes: 0 };
            return {
                "Student Name": student.full_name,
                "Room": student.room_allocations[0]?.rooms?.room_number || 'N/A',
                "Status": record.status,
                "Late (Mins)": record.late_minutes,
                "Note": record.note,
            };
        });
        const csv = Papa.unparse(exportData);
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement("a");
        const url = URL.createObjectURL(blob);
        link.setAttribute("href", url);
        link.setAttribute("download", `attendance_${filters.date}_${filters.sessionType}.csv`);
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        toast.success("CSV export downloaded.");
    };

    const filteredStudents = students.filter(student =>
        student.full_name.toLowerCase().includes(debouncedSearchTerm.toLowerCase())
    );
    
    const statusOptions = [
        { label: 'Present', value: 'Present' },
        { label: 'Absent', value: 'Absent' },
        { label: 'Late', value: 'Late' },
        { label: 'Excused', value: 'Excused' },
    ];

    return (
        <>
            <PageHeader title="Mark Attendance" />
            
            {/* Toolbar */}
            <div className="bg-base-100 dark:bg-dark-base-200 p-4 rounded-xl shadow-lg mb-6 sticky top-24 z-20">
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 items-end">
                    <div>
                        <label className="text-xs font-medium text-base-content-secondary">Date</label>
                        <input type="date" value={filters.date} onChange={e => handleFilterChange('date', e.target.value)} className="input" />
                    </div>
                    <div>
                        <label className="text-xs font-medium text-base-content-secondary">Session Type</label>
                        <select value={filters.sessionType} onChange={e => handleFilterChange('sessionType', e.target.value)} className="input">
                            <option>NightRoll</option>
                            <option>Morning</option>
                            <option>Evening</option>
                        </select>
                    </div>
                    <div>
                        <label className="text-xs font-medium text-base-content-secondary">Course (Optional)</label>
                        <input type="text" placeholder="e.g. B.Tech" value={filters.course} onChange={e => handleFilterChange('course', e.target.value)} className="input" />
                    </div>
                    <button onClick={loadSessionAndStudents} disabled={loading} className="btn-primary py-2.5">
                        {loading ? <Loader className="animate-spin" /> : 'Load Session'}
                    </button>
                </div>
                {session && (
                    <div className="mt-4 pt-4 border-t border-base-200 dark:border-dark-base-300 flex flex-wrap gap-2 items-center justify-between">
                         <input type="text" placeholder="Search students..." value={filters.searchTerm} onChange={e => handleFilterChange('searchTerm', e.target.value)} className="input w-full md:w-auto" />
                        <div className="flex gap-2">
                            <button onClick={() => handleBulkMark('Present')} className="btn-secondary">Mark All Present</button>
                            <button onClick={handleSave} disabled={saving} className="btn-primary">
                                {saving ? <Loader className="animate-spin" /> : 'Save Attendance'}
                            </button>
                             <button onClick={handleExport} className="btn-outline p-2"><FileDown className="w-5 h-5" /></button>
                        </div>
                    </div>
                )}
            </div>

            {/* Attendance Table */}
            <div className="bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-lg overflow-hidden">
                {loading ? (
                    <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>
                ) : filteredStudents.length > 0 ? (
                    <div className="overflow-x-auto">
                        <table className="min-w-full">
                            <thead className="bg-base-200/50 dark:bg-dark-base-300/50">
                                <tr>
                                    <th className="th">Student Name</th>
                                    <th className="th">Room</th>
                                    <th className="th w-1/3">Status</th>
                                    <th className="th">Details</th>
                                </tr>
                            </thead>
                            <motion.tbody className="divide-y divide-base-200 dark:divide-dark-base-300">
                                {filteredStudents.map(student => (
                                    <motion.tr key={student.id} layout className="hover:bg-base-200/50 dark:hover:bg-dark-base-300/50">
                                        <td className="td font-semibold">{student.full_name}</td>
                                        <td className="td">{student.room_allocations[0]?.rooms?.room_number || 'N/A'}</td>
                                        <td className="td">
                                            <SegmentedControl
                                                options={statusOptions}
                                                value={records[student.id]?.status || 'Present'}
                                                onChange={status => handleRecordChange(student.id, 'status', status)}
                                            />
                                        </td>
                                        <td className="td">
                                            <div className="flex gap-2">
                                                {records[student.id]?.status === 'Late' && (
                                                    <input
                                                        type="number"
                                                        placeholder="Mins"
                                                        value={records[student.id]?.late_minutes || ''}
                                                        onChange={e => handleRecordChange(student.id, 'late_minutes', e.target.value)}
                                                        className="input w-20"
                                                    />
                                                )}
                                                <input
                                                    type="text"
                                                    placeholder="Note..."
                                                    value={records[student.id]?.note || ''}
                                                    onChange={e => handleRecordChange(student.id, 'note', e.target.value)}
                                                    className="input w-full"
                                                />
                                            </div>
                                        </td>
                                    </motion.tr>
                                ))}
                            </motion.tbody>
                        </table>
                    </div>
                ) : (
                    <EmptyState
                        icon={<Users className="w-full h-full" />}
                        title="No Students Found"
                        message={session ? "No students match the current filters." : "Load a session to begin marking attendance."}
                    />
                )}
            </div>
        </>
    );
};

export default AttendancePage;
