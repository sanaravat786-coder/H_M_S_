import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import PageHeader from '../components/ui/PageHeader';
import { Alert, AlertDescription, AlertTitle } from "../components/ui/alert";
import { Check, X, Clock, Calendar as CalendarIcon, Sun, Moon, TreePalm, User, Loader } from 'lucide-react';

const AttendancePage = () => {
    const [students, setStudents] = useState([]);
    const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
    const [session, setSession] = useState('morning');
    const [attendance, setAttendance] = useState({});
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [success, setSuccess] = useState('');

    useEffect(() => {
        fetchStudents();
    }, []);

    useEffect(() => {
        if (students.length > 0) {
            fetchAttendance();
        }
    }, [date, session, students]);

    const fetchStudents = async () => {
        setLoading(true);
        const { data, error } = await supabase
            .from('profiles')
            .select('id, full_name')
            .eq('role', 'student')
            .order('full_name');

        if (error) {
            setError('Failed to fetch students.');
            console.error(error);
        } else {
            setStudents(data);
            const initialAttendance = data.reduce((acc, student) => {
                acc[student.id] = 'Present';
                return acc;
            }, {});
            setAttendance(initialAttendance);
        }
        setLoading(false);
    };

    const fetchAttendance = async () => {
        setLoading(true);
        setError('');
        const sessionTypeForDb = session === 'morning' ? 'Morning' : 'Evening';
        const { data: sessionData, error: sessionError } = await supabase.rpc('get_or_create_session', {
            p_date: date,
            p_session_type: sessionTypeForDb
        });

        if (sessionError) {
            setError('Failed to get or create attendance session.');
            console.error(sessionError);
            setLoading(false);
            return;
        }

        const { data: attendanceData, error: attendanceError } = await supabase
            .from('attendance_records')
            .select('student_id, status')
            .eq('session_id', sessionData);

        if (attendanceError) {
            setError('Failed to fetch attendance records.');
            console.error(attendanceError);
        } else {
            const newAttendance = {};
            students.forEach(student => {
                const record = attendanceData.find(a => a.student_id === student.id);
                newAttendance[student.id] = record ? record.status : 'Present';
            });
            setAttendance(newAttendance);
        }
        setLoading(false);
    };

    const handleAttendanceChange = (studentId, status) => {
        setAttendance(prev => ({ ...prev, [studentId]: status }));
    };
    
    const statusIcons = {
        'Leave': <Clock className="h-5 w-5 text-yellow-500" />,
        'Holiday': <TreePalm className="h-5 w-5 text-blue-500" />
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError('');
        setSuccess('');

        const sessionTypeForDb = session === 'morning' ? 'Morning' : 'Evening';
        const { data: sessionData, error: sessionError } = await supabase.rpc('get_or_create_session', {
            p_date: date,
            p_session_type: sessionTypeForDb
        });

        if (sessionError) {
            setError('Failed to get or create attendance session.');
            console.error(sessionError);
            setLoading(false);
            return;
        }

        const records = Object.entries(attendance).map(([student_id, status]) => ({
            session_id: sessionData,
            student_id,
            status,
        }));

        const { error: upsertError } = await supabase
            .from('attendance_records')
            .upsert(records, { onConflict: 'session_id, student_id' });

        if (upsertError) {
            setError('Failed to save attendance.');
            console.error(upsertError);
        } else {
            setSuccess('Attendance saved successfully!');
        }

        setLoading(false);
        setTimeout(() => setSuccess(''), 3000);
    };

    return (
        <>
            <PageHeader title="Mark Attendance" />
            
            <form onSubmit={handleSubmit} className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-2xl shadow-lg border border-base-200 dark:border-dark-base-300">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                    <div>
                        <label htmlFor="date" className="block text-sm font-medium text-base-content-secondary mb-1">Date</label>
                        <div className="relative">
                            <input
                                type="date"
                                id="date"
                                value={date}
                                onChange={(e) => setDate(e.target.value)}
                                className="w-full pl-10 pr-4 py-2 border border-base-300 dark:border-dark-base-300 rounded-lg bg-base-100 dark:bg-dark-base-200 focus:ring-primary focus:border-primary"
                            />
                            <CalendarIcon className="absolute left-3 top-1/2 -translate-y-1/2 h-5 w-5 text-base-content-secondary" />
                        </div>
                    </div>
                    <div>
                        <label htmlFor="session" className="block text-sm font-medium text-base-content-secondary mb-1">Session</label>
                        <div className="flex items-center space-x-2 bg-base-200 dark:bg-dark-base-300 border border-base-200 dark:border-dark-base-300 p-1 rounded-lg">
                            <button type="button" onClick={() => setSession('morning')} className={`flex-1 flex items-center justify-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors ${session === 'morning' ? 'bg-base-100 dark:bg-dark-base-200 shadow-sm text-primary' : 'hover:bg-base-300/50 dark:hover:bg-dark-base-100/50'}`}>
                                <Sun className="h-4 w-4" /> Morning
                            </button>
                            <button type="button" onClick={() => setSession('evening')} className={`flex-1 flex items-center justify-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors ${session === 'evening' ? 'bg-base-100 dark:bg-dark-base-200 shadow-sm text-primary' : 'hover:bg-base-300/50 dark:hover:bg-dark-base-100/50'}`}>
                                <Moon className="h-4 w-4" /> Evening
                            </button>
                        </div>
                    </div>
                </div>

                {error && <Alert variant="destructive" className="mb-4"><AlertTitle>Error</AlertTitle><AlertDescription>{error}</AlertDescription></Alert>}
                {success && <Alert variant="success" className="mb-4"><AlertTitle>Success</AlertTitle><AlertDescription>{success}</AlertDescription></Alert>}

                <div className="overflow-x-auto">
                    <table className="min-w-full divide-y divide-base-200 dark:divide-dark-base-300">
                        <thead className="bg-base-200/50 dark:bg-dark-base-300/50">
                            <tr>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-base-content-secondary uppercase tracking-wider">Student</th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-base-content-secondary uppercase tracking-wider">Status</th>
                            </tr>
                        </thead>
                        <tbody className="bg-base-100 dark:bg-dark-base-200 divide-y divide-base-200 dark:divide-dark-base-300">
                            {loading && !students.length ? (
                                [...Array(5)].map((_, i) => (
                                    <tr key={i}>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <div className="flex items-center">
                                                <div className="h-8 w-8 bg-base-200 dark:bg-dark-base-300 rounded-full animate-pulse"></div>
                                                <div className="ml-4 h-4 w-40 bg-base-200 dark:bg-dark-base-300 rounded animate-pulse"></div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <div className="flex items-center space-x-2">
                                                <div className="h-8 w-24 bg-base-200 dark:bg-dark-base-300 rounded-lg animate-pulse"></div>
                                                <div className="h-8 w-24 bg-base-200 dark:bg-dark-base-300 rounded-lg animate-pulse"></div>
                                            </div>
                                        </td>
                                    </tr>
                                ))
                            ) : students.map((student) => (
                                <tr key={student.id}>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <div className="flex items-center">
                                            <User className="h-5 w-5 mr-3 text-base-content-secondary" />
                                            <span className="font-medium">{student.full_name}</span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <div className="flex items-center space-x-4">
                                            <div className="flex items-center space-x-2">
                                                <button
                                                    type="button"
                                                    onClick={() => handleAttendanceChange(student.id, 'Present')}
                                                    className={`px-4 py-2 text-sm font-semibold rounded-lg flex items-center gap-2 transition-all transform hover:scale-105 ${attendance[student.id] === 'Present' ? 'bg-green-500 text-white shadow-lg' : 'bg-base-200 dark:bg-dark-base-300 text-base-content-secondary'}`}
                                                >
                                                    <Check size={16} /> Present
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => handleAttendanceChange(student.id, 'Absent')}
                                                    className={`px-4 py-2 text-sm font-semibold rounded-lg flex items-center gap-2 transition-all transform hover:scale-105 ${attendance[student.id] === 'Absent' ? 'bg-red-500 text-white shadow-lg' : 'bg-base-200 dark:bg-dark-base-300 text-base-content-secondary'}`}
                                                >
                                                    <X size={16} /> Absent
                                                </button>
                                            </div>
                                            
                                            <div className="flex items-center space-x-2">
                                                {Object.entries(statusIcons).map(([status, icon]) => (
                                                    <button
                                                        key={status}
                                                        type="button"
                                                        onClick={() => handleAttendanceChange(student.id, status)}
                                                        className={`p-2 rounded-full transition-transform transform hover:scale-110 ${attendance[student.id] === status ? 'ring-2 ring-primary ring-offset-2 ring-offset-base-100 dark:ring-offset-dark-base-200' : 'opacity-50 hover:opacity-100'}`}
                                                        title={status}
                                                    >
                                                        {icon}
                                                    </button>
                                                ))}
                                            </div>
                                        </div>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
                <div className="mt-6 flex justify-end">
                    <button
                        type="submit"
                        disabled={loading}
                        className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-primary-content bg-primary hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary disabled:opacity-50"
                    >
                        {loading ? <Loader className="animate-spin h-5 w-5 mr-2" /> : null}
                        {loading ? 'Saving...' : 'Save Attendance'}
                    </button>
                </div>
            </form>
        </>
    );
};

export default AttendancePage;
