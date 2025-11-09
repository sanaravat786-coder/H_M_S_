import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';
import toast from 'react-hot-toast';
import { Check, Loader, Sun, Moon, Info } from 'lucide-react';

const SessionCard = ({ sessionType, status, onMarkPresent, loading }) => {
    const isMarked = status && status !== 'unmarked';
    const icon = sessionType === 'morning' ? <Sun /> : <Moon />;

    return (
        <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-xl shadow-md flex items-center justify-between">
            <div className="flex items-center gap-4">
                <div className="p-3 bg-primary/10 text-primary rounded-full">{icon}</div>
                <div>
                    <h3 className="font-bold capitalize text-lg">{sessionType} Session</h3>
                    <p className="text-sm text-base-content-secondary">Status: <span className={`font-semibold ${isMarked ? 'text-green-500' : 'text-yellow-500'}`}>{isMarked ? status : 'Not Marked'}</span></p>
                </div>
            </div>
            {!isMarked && (
                <button
                    onClick={onMarkPresent}
                    disabled={loading}
                    className="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50"
                >
                    {loading ? <Loader className="animate-spin h-5 w-5" /> : <Check className="h-5 w-5 mr-2" />}
                    Mark Present
                </button>
            )}
        </div>
    );
};

const AttendanceMarker = () => {
    const { user } = useAuth();
    const [attendance, setAttendance] = useState({ morning: 'loading', evening: 'loading' });
    const [loading, setLoading] = useState({ morning: false, evening: false });

    const fetchAttendanceStatus = useCallback(async () => {
        if (!user) return;

        const today = new Date().toISOString().slice(0, 10);
        const newAttendance = { morning: 'unmarked', evening: 'unmarked' };

        try {
            const sessionMapping = { morning: 'Morning', evening: 'Evening' };
            for (const sessionKey of ['morning', 'evening']) {
                const sessionTypeForDb = sessionMapping[sessionKey];
                const { data: sessionData, error: sessionError } = await supabase.rpc('get_or_create_session', {
                    p_date: today,
                    p_session_type: sessionTypeForDb
                });

                if (sessionError) throw sessionError;

                const { data: record, error: recordError } = await supabase
                    .from('attendance_records')
                    .select('status')
                    .eq('session_id', sessionData)
                    .eq('student_id', user.id)
                    .maybeSingle();
                
                if (recordError) throw recordError;

                if (record) {
                    newAttendance[sessionKey] = record.status;
                }
            }
        } catch (error) {
            console.error("Error fetching attendance status:", error);
            toast.error('Could not fetch attendance status.');
            newAttendance.morning = 'error';
            newAttendance.evening = 'error';
        }
        setAttendance(newAttendance);
    }, [user]);

    useEffect(() => {
        fetchAttendanceStatus();
    }, [fetchAttendanceStatus]);

    const handleMarkPresent = async (sessionType) => {
        if (!user) return;
        setLoading(prev => ({ ...prev, [sessionType]: true }));

        try {
            const today = new Date().toISOString().slice(0, 10);
            const sessionTypeForDb = sessionType === 'morning' ? 'Morning' : 'Evening';
            
            const { data: sessionId, error: sessionError } = await supabase.rpc('get_or_create_session', {
                p_date: today,
                p_session_type: sessionTypeForDb
            });
            if (sessionError) throw sessionError;

            const { error: upsertError } = await supabase
                .from('attendance_records')
                .upsert({
                    session_id: sessionId,
                    student_id: user.id,
                    status: 'Present'
                }, { onConflict: 'session_id, student_id' });
            
            if (upsertError) throw upsertError;

            toast.success(`Attendance marked for ${sessionType} session.`);
            setAttendance(prev => ({ ...prev, [sessionType]: 'Present' }));

        } catch (error) {
            toast.error(`Failed to mark attendance: ${error.message}`);
        } finally {
            setLoading(prev => ({ ...prev, [sessionType]: false }));
        }
    };
    
    return (
        <div className="bg-base-200/50 dark:bg-dark-base-300/30 p-6 rounded-2xl shadow-lg">
            <h2 className="text-xl font-bold mb-4">Today's Attendance</h2>
            <div className="space-y-4">
                {attendance.morning === 'loading' ? (
                    <div className="flex justify-center items-center h-24"><Loader className="animate-spin" /></div>
                ) : (
                    <>
                        <SessionCard
                            sessionType="morning"
                            status={attendance.morning}
                            loading={loading.morning}
                            onMarkPresent={() => handleMarkPresent('morning')}
                        />
                        <SessionCard
                            sessionType="evening"
                            status={attendance.evening}
                            loading={loading.evening}
                            onMarkPresent={() => handleMarkPresent('evening')}
                        />
                    </>
                )}
            </div>
            <div className="mt-4 p-3 bg-blue-500/10 text-blue-700 dark:text-blue-300 rounded-lg flex items-start text-sm">
                <Info className="w-5 h-5 mr-3 mt-0.5 flex-shrink-0" />
                <p>You can mark your attendance once per session. If marked incorrectly, please contact the hostel administration.</p>
            </div>
        </div>
    );
};

export default AttendanceMarker;
