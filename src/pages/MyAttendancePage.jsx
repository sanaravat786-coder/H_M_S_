import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import toast from 'react-hot-toast';
import { Loader, ChevronLeft, ChevronRight } from 'lucide-react';
import PageHeader from '../components/ui/PageHeader';

const AttendanceCalendar = ({ data, month, year }) => {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const firstDayOfMonth = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    const statusColors = {
        Present: 'bg-green-500/80',
        Absent: 'bg-red-500/80',
        Late: 'bg-yellow-500/80',
        Excused: 'bg-blue-500/80',
        Unmarked: 'bg-base-300/50 dark:bg-dark-base-300/50',
    };

    return (
        <div className="grid grid-cols-7 gap-2">
            {days.map(day => (
                <div key={day} className="text-center font-semibold text-xs text-base-content-secondary">{day}</div>
            ))}
            {Array.from({ length: firstDayOfMonth }).map((_, i) => <div key={`empty-${i}`} />)}
            {Array.from({ length: daysInMonth }).map((_, dayIndex) => {
                const day = dayIndex + 1;
                const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
                const record = data.find(d => d.day === dateStr);
                const status = record ? record.status : 'Unmarked';

                return (
                    <div key={day} className="relative aspect-square border border-base-200 dark:border-dark-base-300 rounded-lg p-1.5 flex flex-col">
                        <span className="font-bold text-sm">{day}</span>
                        <div className={`absolute bottom-1.5 right-1.5 w-3 h-3 rounded-full ${statusColors[status]}`} title={status}></div>
                    </div>
                );
            })}
        </div>
    );
};

const MyAttendancePage = () => {
    const { user } = useAuth();
    const [date, setDate] = useState(new Date());
    const [calendarData, setCalendarData] = useState([]);
    const [stats, setStats] = useState({ present: 0, absent: 0, late: 0, excused: 0, total: 0, percentage: 0 });
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchMyAttendance = async () => {
            if (!user) return;
            setLoading(true);
            try {
                const month = date.getMonth() + 1;
                const year = date.getFullYear();
                
                // This RPC needs to be created in Supabase
                const { data, error } = await supabase.rpc('student_attendance_calendar', {
                    p_student_id: user.id,
                    p_month: month,
                    p_year: year
                });

                if (error) throw error;
                setCalendarData(data || []);

                // Calculate stats
                let present = 0, absent = 0, late = 0, excused = 0;
                (data || []).forEach(rec => {
                    if (rec.status === 'Present') present++;
                    if (rec.status === 'Absent') absent++;
                    if (rec.status === 'Late') late++;
                    if (rec.status === 'Excused') excused++;
                });
                const totalMarked = present + absent + late + excused;
                const percentage = totalMarked > 0 ? Math.round((present + late) / totalMarked * 100) : 100;
                setStats({ present, absent, late, excused, total: totalMarked, percentage });

            } catch (error) {
                toast.error(`Failed to fetch attendance: ${error.message}`);
            } finally {
                setLoading(false);
            }
        };
        fetchMyAttendance();
    }, [user, date]);

    const changeMonth = (offset) => {
        setDate(prev => {
            const newDate = new Date(prev);
            newDate.setMonth(newDate.getMonth() + offset);
            return newDate;
        });
    };

    return (
        <>
            <PageHeader title="My Attendance" />
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <div className="lg:col-span-2 bg-base-100 dark:bg-dark-base-200 p-6 rounded-xl shadow-lg">
                    <div className="flex justify-between items-center mb-4">
                        <h3 className="text-xl font-bold">{date.toLocaleString('default', { month: 'long', year: 'numeric' })}</h3>
                        <div className="flex items-center gap-2">
                            <button onClick={() => changeMonth(-1)} className="btn-icon"><ChevronLeft /></button>
                            <button onClick={() => changeMonth(1)} className="btn-icon"><ChevronRight /></button>
                        </div>
                    </div>
                    {loading ? (
                        <div className="flex justify-center items-center h-96"><Loader className="animate-spin" /></div>
                    ) : (
                        <AttendanceCalendar data={calendarData} month={date.getMonth()} year={date.getFullYear()} />
                    )}
                </div>
                <div className="space-y-6">
                    <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-xl shadow-lg text-center">
                        <p className="text-base-content-secondary text-sm">Overall Attendance</p>
                        <p className="text-5xl font-bold text-primary dark:text-dark-primary mt-2">{stats.percentage}%</p>
                    </div>
                     <div className="bg-base-100 dark:bg-dark-base-200 p-6 rounded-xl shadow-lg">
                        <h4 className="font-bold mb-4">Monthly Summary</h4>
                        <ul className="space-y-2 text-sm">
                            <li className="flex justify-between items-center"><span>Present</span><span className="font-bold text-green-500">{stats.present}</span></li>
                            <li className="flex justify-between items-center"><span>Absent</span><span className="font-bold text-red-500">{stats.absent}</span></li>
                            <li className="flex justify-between items-center"><span>Late</span><span className="font-bold text-yellow-500">{stats.late}</span></li>
                            <li className="flex justify-between items-center"><span>Excused</span><span className="font-bold text-blue-500">{stats.excused}</span></li>
                            <li className="flex justify-between items-center border-t border-base-200 dark:border-dark-base-300 mt-2 pt-2"><strong>Total Marked</strong><strong>{stats.total}</strong></li>
                        </ul>
                    </div>
                </div>
            </div>
        </>
    );
};

export default MyAttendancePage;
