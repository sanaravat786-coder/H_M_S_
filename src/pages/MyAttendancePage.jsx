import React, { useState, useEffect, useMemo } from 'react';
import { useLocation } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import PageHeader from '../components/ui/PageHeader';
import { Check, X, Clock, PalmTree, ChevronLeft, ChevronRight, Download, Loader } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../components/ui/alert'; // Assuming alert component exists
import jsPDF from 'jspdf';
import 'jspdf-autotable';

const MyAttendancePage = () => {
    const { user } = useAuth();
    const location = useLocation();
    
    // Determine whose attendance to show: a specific student (for admins) or the logged-in user.
    const viewAsAdmin = location.state?.studentId;
    const studentId = viewAsAdmin || user?.id;
    const studentName = location.state?.studentName || user?.user_metadata?.full_name;

    const [currentDate, setCurrentDate] = useState(new Date());
    const [attendanceData, setAttendanceData] = useState({});
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    const currentMonth = currentDate.getMonth();
    const currentYear = currentDate.getFullYear();

    useEffect(() => {
        if (studentId) {
            fetchAttendance();
        }
    }, [studentId, currentMonth, currentYear]);

    const fetchAttendance = async () => {
        setLoading(true);
        setError('');
        const { data, error: rpcError } = await supabase.rpc('get_monthly_attendance_for_student', {
            p_student_id: studentId,
            p_month: currentMonth + 1,
            p_year: currentYear
        });

        if (rpcError) {
            setError('Failed to fetch attendance data.');
            console.error(rpcError);
            setAttendanceData({});
        } else {
            const dataMap = (data || []).reduce((acc, record) => {
                // Adjust for timezone issues by creating date in UTC
                const recordDate = new Date(record.day);
                const dayOfMonth = recordDate.getUTCDate();
                acc[dayOfMonth] = record.status;
                return acc;
            }, {});
            setAttendanceData(dataMap);
        }
        setLoading(false);
    };

    const daysInMonth = new Date(currentYear, currentMonth + 1, 0).getDate();
    const firstDayOfMonth = new Date(currentYear, currentMonth, 1).getDay();

    const calendarDays = useMemo(() => {
        const days = [];
        for (let i = 0; i < firstDayOfMonth; i++) {
            days.push({ key: `empty-${i}`, empty: true });
        }
        for (let day = 1; day <= daysInMonth; day++) {
            days.push({ key: day, day, status: attendanceData[day] });
        }
        return days;
    }, [firstDayOfMonth, daysInMonth, attendanceData]);

    const handlePrevMonth = () => setCurrentDate(new Date(currentYear, currentMonth - 1, 1));
    const handleNextMonth = () => setCurrentDate(new Date(currentYear, currentMonth + 1, 1));

    const downloadReport = () => {
        const doc = new jsPDF();
        const monthName = currentDate.toLocaleString('default', { month: 'long' });
        const title = `Attendance for ${studentName} - ${monthName} ${currentYear}`;

        doc.setFontSize(18);
        doc.text(title, 14, 22);
        
        const tableColumn = ["Date", "Status"];
        const tableRows = [];

        calendarDays.forEach(item => {
            if (!item.empty) {
                const dateStr = `${item.day} ${monthName} ${currentYear}`;
                const row = [dateStr, item.status || 'No Record'];
                tableRows.push(row);
            }
        });

        doc.autoTable({
            head: [tableColumn],
            body: tableRows,
            startY: 30,
            theme: 'grid',
            headStyles: { fillColor: '#4f46e5' },
        });

        doc.save(`attendance_${studentName}_${monthName}_${currentYear}.pdf`);
    };
    
    const statusConfig = {
        'Present': { icon: <Check className="h-5 w-5" />, color: 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300', ring: 'ring-green-500' },
        'Absent': { icon: <X className="h-5 w-5" />, color: 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300', ring: 'ring-red-500' },
        'Leave': { icon: <Clock className="h-5 w-5" />, color: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300', ring: 'ring-yellow-500' },
        'Holiday': { icon: <PalmTree className="h-5 w-5" />, color: 'bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-300', ring: 'ring-blue-500' },
    };

    const weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const pageTitle = viewAsAdmin ? `Attendance: ${studentName}` : "My Attendance";

    return (
        <>
            <PageHeader title={pageTitle} />
            
            <div className="bg-base-100 dark:bg-dark-base-200 p-4 sm:p-6 rounded-2xl shadow-lg border border-base-200 dark:border-dark-base-300">
                <div className="flex flex-col sm:flex-row justify-between items-center mb-6">
                    <div className="flex items-center gap-2 sm:gap-4">
                        <button onClick={handlePrevMonth} className="p-2 rounded-full hover:bg-base-200 dark:hover:bg-dark-base-300 transition-colors"><ChevronLeft /></button>
                        <h2 className="text-xl font-bold text-center w-48">{currentDate.toLocaleString('default', { month: 'long' })} {currentYear}</h2>
                        <button onClick={handleNextMonth} className="p-2 rounded-full hover:bg-base-200 dark:hover:bg-dark-base-300 transition-colors"><ChevronRight /></button>
                    </div>
                    <button onClick={downloadReport} className="mt-4 sm:mt-0 inline-flex items-center justify-center gap-2 px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-primary-content bg-primary hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary">
                        <Download className="h-4 w-4" />
                        Download Report
                    </button>
                </div>

                {error && <Alert variant="destructive" className="mb-4"><AlertTitle>Error</AlertTitle><AlertDescription>{error}</AlertDescription></Alert>}

                <div className="grid grid-cols-7 gap-1 sm:gap-2 text-center font-semibold text-base-content-secondary dark:text-dark-base-content-secondary mb-2">
                    {weekDays.map(day => <div key={day} className="py-2">{day}</div>)}
                </div>

                {loading ? (
                    <div className="flex justify-center items-center h-96">
                        <Loader className="h-8 w-8 animate-spin text-primary" />
                    </div>
                ) : (
                    <div className="grid grid-cols-7 gap-1 sm:gap-2">
                        {calendarDays.map(item => {
                            if (item.empty) return <div key={item.key} className="h-20 sm:h-24 w-full rounded-lg"></div>;
                            
                            const config = statusConfig[item.status];
                            const isToday = new Date().toDateString() === new Date(currentYear, currentMonth, item.day).toDateString();

                            return (
                                <div key={item.key} className={`relative h-20 sm:h-24 w-full flex flex-col items-center justify-center rounded-lg p-2 transition-all ${config ? config.color : 'bg-base-200/50 dark:bg-dark-base-300/50'} ${isToday ? `ring-2 ${config ? config.ring : 'ring-primary'}` : ''}`}>
                                    <div className="text-sm sm:text-base font-bold">{item.day}</div>
                                    {config && <div className="mt-2">{config.icon}</div>}
                                    {!config && <div className="mt-2 h-5 w-5"></div>}
                                </div>
                            );
                        })}
                    </div>
                )}

                <div className="mt-8 flex flex-wrap justify-center gap-x-4 sm:gap-x-6 gap-y-2 text-sm text-base-content-secondary dark:text-dark-base-content-secondary">
                    {Object.entries(statusConfig).map(([status, { icon }]) => (
                        <div key={status} className="flex items-center gap-2">
                            {React.cloneElement(icon, { className: "h-4 w-4" })}
                            <span>{status}</span>
                        </div>
                    ))}
                </div>
            </div>
        </>
    );
};

export default MyAttendancePage;
