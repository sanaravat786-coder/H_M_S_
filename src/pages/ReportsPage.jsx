import React, { useState } from 'react';
import { FileDown, Loader } from 'lucide-react';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import Papa from 'papaparse';

const ReportButton = ({ onClick, isLoading, children }) => (
    <button
        onClick={onClick}
        disabled={isLoading}
        className="flex items-center justify-center w-full px-4 py-3 font-medium text-primary-content bg-primary rounded-lg hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary dark:focus:ring-offset-dark-base-200 transition-colors disabled:opacity-60"
    >
        {isLoading ? (
            <Loader className="w-5 h-5 mr-2 animate-spin" />
        ) : (
            <FileDown className="w-5 h-5 mr-2" />
        )}
        {isLoading ? 'Generating...' : children}
    </button>
);

const ReportsPage = () => {
    const [loading, setLoading] = useState({
        occupancy: false,
        fees: false,
        visitors: false,
    });

    const downloadCSV = (data, filename) => {
        if (!data || data.length === 0) {
            toast.error('No data available to generate this report.');
            return;
        }
        try {
            const csv = Papa.unparse(data);
            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);
            link.setAttribute('href', url);
            link.setAttribute('download', filename);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            toast.success(`${filename} downloaded successfully!`);
        } catch (error) {
            toast.error('Failed to create CSV file.');
            console.error("CSV Generation Error:", error);
        }
    };

    const handleOccupancyReport = async () => {
        setLoading(prev => ({ ...prev, occupancy: true }));
        try {
            const { data, error } = await supabase
                .from('rooms')
                .select('room_number, type, status, occupants')
                .order('room_number');

            if (error) throw error;
            downloadCSV(data, 'occupancy_report.csv');
        } catch (error) {
            toast.error(`Failed to generate report: ${error.message}`);
        } finally {
            setLoading(prev => ({ ...prev, occupancy: false }));
        }
    };

    const handleFeeReport = async () => {
        setLoading(prev => ({ ...prev, fees: true }));
        try {
            const { data, error } = await supabase
                .from('fees')
                .select('amount, due_date, status, payment_date, students(full_name)')
                .order('due_date');

            if (error) throw error;
            
            const formattedData = data.map(fee => ({
                student_name: fee.students?.full_name || 'N/A',
                amount: fee.amount,
                due_date: new Date(fee.due_date).toLocaleDateString(),
                status: fee.status,
                payment_date: fee.payment_date ? new Date(fee.payment_date).toLocaleDateString() : 'N/A',
            }));

            downloadCSV(formattedData, 'fee_collection_report.csv');
        } catch (error) {
            toast.error(`Failed to generate report: ${error.message}`);
        } finally {
            setLoading(prev => ({ ...prev, fees: false }));
        }
    };

    const handleVisitorReport = async () => {
        setLoading(prev => ({ ...prev, visitors: true }));
        try {
            const { data, error } = await supabase
                .from('visitors')
                .select('visitor_name, check_in_time, check_out_time, status, students(full_name)')
                .order('check_in_time');

            if (error) throw error;

            const formattedData = data.map(visitor => ({
                visitor_name: visitor.visitor_name,
                visiting_student: visitor.students?.full_name || 'N/A',
                check_in_time: new Date(visitor.check_in_time).toLocaleString(),
                check_out_time: visitor.check_out_time ? new Date(visitor.check_out_time).toLocaleString() : 'N/A',
                status: visitor.status,
            }));

            downloadCSV(formattedData, 'visitor_log_report.csv');
        } catch (error) {
            toast.error(`Failed to generate report: ${error.message}`);
        } finally {
            setLoading(prev => ({ ...prev, visitors: false }));
        }
    };

    return (
        <>
            <h1 className="text-3xl font-bold text-base-content dark:text-dark-base-content mb-6">Generate Reports</h1>
            <div className="bg-base-100 dark:bg-dark-base-200 p-8 rounded-xl shadow-lg transition-colors">
                <p className="text-base-content-secondary dark:text-dark-base-content-secondary mb-6">Select a report to download as a CSV file.</p>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    <ReportButton onClick={handleOccupancyReport} isLoading={loading.occupancy}>
                        Occupancy Report
                    </ReportButton>
                    <ReportButton onClick={handleFeeReport} isLoading={loading.fees}>
                        Fee Collection Report
                    </ReportButton>
                    <ReportButton onClick={handleVisitorReport} isLoading={loading.visitors}>
                        Visitor Log Report
                    </ReportButton>
                </div>
            </div>
        </>
    );
};

export default ReportsPage;
