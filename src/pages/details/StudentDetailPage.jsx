import React, { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader, ClipboardCheck } from 'lucide-react';
import toast from 'react-hot-toast';

const StudentDetailPage = () => {
    const { id } = useParams();
    const [student, setStudent] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchStudent = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('students')
                .select('*')
                .eq('id', id)
                .single();

            if (error) {
                toast.error('Student not found.');
            } else {
                setStudent(data);
            }
            setLoading(false);
        };

        fetchStudent();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!student) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Student not found</div>;
    }

    return (
        <>
        <DetailPageLayout title={student.full_name} backTo="/students">
            <DetailItem label="Full Name" value={student.full_name} />
            <DetailItem label="Email" value={student.email} />
            <DetailItem label="Course" value={student.course} />
            <DetailItem label="Contact" value={student.contact} />
            <DetailItem label="Joined On" value={student.created_at ? new Date(student.created_at).toLocaleDateString() : 'N/A'} />
        </DetailPageLayout>
         <div className="mt-8">
            <h2 className="text-2xl font-bold mb-4">Quick Actions</h2>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <Link to="/my-attendance" state={{ studentId: student.id, studentName: student.full_name }} className="flex items-center gap-3 p-4 bg-base-100 dark:bg-dark-base-200 rounded-lg shadow-md hover:bg-base-200 dark:hover:bg-dark-base-300 transition-colors">
                    <ClipboardCheck className="w-6 h-6 text-primary" />
                    <span className="font-semibold">View Attendance</span>
                </Link>
            </div>
        </div>
        </>
    );
};

export default StudentDetailPage;
